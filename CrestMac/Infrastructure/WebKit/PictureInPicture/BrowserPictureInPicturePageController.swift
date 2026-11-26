import WebKit

@MainActor
final class BrowserPictureInPicturePageController: BrowserPagePictureInPictureController,
    BrowserAutomaticPictureInPictureClient
{
    // MARK: - Types

    private struct FrameCandidate {
        let frame: WKFrameInfo
        let documentID: String
        let videoID: String
        let score: Double
    }

    private struct AutomaticRequest {
        let id: UUID
        let candidate: FrameCandidate
    }

    private protocol BridgeMessage: Decodable {
        var documentID: String { get }

        @MainActor
        func apply(to controller: BrowserPictureInPicturePageController, frame: WKFrameInfo)
    }

    private struct BridgeEnvelope: Decodable {
        let kind: String
    }

    private struct RemovedMessage: BridgeMessage {
        let documentID: String

        @MainActor
        func apply(to controller: BrowserPictureInPicturePageController, frame: WKFrameInfo) {
            controller.removeDocument(documentID)
        }
    }

    private struct RequestMessage: BridgeMessage {
        let documentID: String
        let requestID: String?
        let succeeded: Bool?

        @MainActor
        func apply(to controller: BrowserPictureInPicturePageController, frame: WKFrameInfo) {
            controller.receiveRequestOutcome(
                documentID: documentID, requestID: requestID, succeeded: succeeded == true)
        }
    }

    private struct StateMessage: BridgeMessage {
        let documentID: String
        let active: Bool?
        let eligible: Bool?
        let videoID: String?
        let score: Double?

        @MainActor
        func apply(to controller: BrowserPictureInPicturePageController, frame: WKFrameInfo) {
            controller.receiveState(
                documentID: documentID, active: active == true, eligible: eligible == true,
                videoID: videoID, score: score, frame: frame)
        }
    }

    // MARK: - Static Variables

    /// How long automatic Picture in Picture waits for the page to report a
    /// floating video before it gives up.
    private static let automaticPictureInPictureTimeout: Duration = .seconds(4)
    private static let messageDecoders: [String: (Data) -> (any BridgeMessage)?] = [
        "removed": { try? JSONDecoder().decode(RemovedMessage.self, from: $0) },
        "request": { try? JSONDecoder().decode(RequestMessage.self, from: $0) },
        "state": { try? JSONDecoder().decode(StateMessage.self, from: $0) },
    ]

    // MARK: - Variables

    private weak var webView: WKWebView?
    private let coordinator: BrowserAutomaticPictureInPictureCoordinator
    private var candidates: [String: FrameCandidate] = [:]
    private var activeDocuments: Set<String> = [] {
        didSet { residencyProtectionMayHaveChanged() }
    }
    private var nativeIsActive = false {
        didSet { residencyProtectionMayHaveChanged() }
    }
    private var acceptsEvents = true
    private var automaticRequest: AutomaticRequest?
    private var completion: (@MainActor (Bool) -> Void)? {
        didSet { residencyProtectionMayHaveChanged() }
    }
    private var timeout: Task<Void, Never>?
    /// Whether the controller kept the page's video on screen when it last
    /// said so.
    private var reportedResidencyProtection = false
    /// Runs when the controller starts or stops keeping the page's video on
    /// screen, so the page reports its media to the core.
    var residencyProtectionChanged: (@MainActor () -> Void)?

    var isPictureInPictureActive: Bool { nativeIsActive || !activeDocuments.isEmpty }
    var canRestoreSource: Bool { acceptsEvents && isPictureInPictureActive }
    var protectsPageResidency: Bool { isPictureInPictureActive || completion != nil }
    var canAutomaticallyEnterPictureInPicture: Bool {
        !candidates.isEmpty && !isPictureInPictureActive && webView != nil
    }

    // MARK: - Initializers

    init(webView: WKWebView, coordinator: BrowserAutomaticPictureInPictureCoordinator = .shared) {
        self.webView = webView
        self.coordinator = coordinator
        coordinator.register(self)
        BrowserPictureInPictureContentBridge.shared.register(self, webView: webView)
    }

    // MARK: - Actions - Picture in Picture

    func requestAutomaticEntry(for trigger: BrowserAutomaticPictureInPictureCoordinator.Trigger) {
        coordinator.request(from: self, for: trigger)
    }

    private func residencyProtectionMayHaveChanged() {
        guard protectsPageResidency != reportedResidencyProtection else { return }
        reportedResidencyProtection = protectsPageResidency
        residencyProtectionChanged?()
    }

    func returnToTab(reconcileLateEntry: @escaping @MainActor () -> Void) {
        coordinator.cancel(self)
        refreshCandidates()
    }

    func navigationDidCommit() { refreshCandidates() }

    private func refreshCandidates() {
        acceptsEvents = true
        webView?.evaluateJavaScript(
            "globalThis.__crestPictureInPicture?.emit(); null",
            in: nil, in: BrowserPictureInPictureContentBridge.contentWorld
        ) { _ in }
    }

    func nativePresentationDidChange(isActive: Bool) {
        nativeIsActive = isActive
        if !isActive {
            activeDocuments.removeAll()
            if completion == nil { automaticRequest = nil }
        }
    }

    func invalidate() {
        acceptsEvents = false
        coordinator.cancel(self)
        if isPictureInPictureActive { webView?.closeAllMediaPresentations(completionHandler: {}) }
        candidates.removeAll()
        activeDocuments.removeAll()
        nativeIsActive = false
    }

    func receive(_ message: WKScriptMessage) {
        guard acceptsEvents, message.webView === webView,
            let decoded = Self.decodeMessage(from: message.body)
        else { return }
        decoded.apply(to: self, frame: message.frameInfo)
    }

    private static func decodeMessage(from body: Any) -> (any BridgeMessage)? {
        guard JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let envelope = try? JSONDecoder().decode(BridgeEnvelope.self, from: data),
            let decode = messageDecoders[envelope.kind],
            let message = decode(data),
            message.documentID.count <= 64
        else { return nil }
        return message
    }

    private func removeDocument(_ documentID: String) {
        candidates[documentID] = nil
        activeDocuments.remove(documentID)
    }

    private func receiveRequestOutcome(documentID: String, requestID: String?, succeeded: Bool) {
        guard requestID == automaticRequest?.id.uuidString else { return }
        if succeeded { activeDocuments.insert(documentID) }
        finish(succeeded: succeeded)
    }

    private func receiveState(
        documentID: String,
        active: Bool,
        eligible: Bool,
        videoID: String?,
        score: Double?,
        frame: WKFrameInfo
    ) {
        if active {
            activeDocuments.insert(documentID)
        } else {
            activeDocuments.remove(documentID)
        }
        guard eligible,
            let videoID, videoID.count <= 32,
            let score, score.isFinite,
            candidates[documentID] != nil || candidates.count < 64
        else {
            candidates[documentID] = nil
            return
        }
        candidates[documentID] = FrameCandidate(
            frame: frame, documentID: documentID, videoID: videoID, score: score)
    }

    func beginAutomaticPictureInPicture(completion: @escaping @MainActor (Bool) -> Void) {
        guard let webView, let candidate = candidates.values.max(by: { $0.score < $1.score }) else {
            completion(false)
            return
        }
        let request = AutomaticRequest(id: UUID(), candidate: candidate)
        automaticRequest = request
        self.completion = completion
        // evaluateJavaScript provides the native user-activation context. Keep
        // the request synchronous inside that evaluation; awaiting discovery
        // before requestPictureInPicture can lose the activation.
        let arguments = [candidate.documentID, candidate.videoID, request.id.uuidString]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
            let encoded = String(data: data, encoding: .utf8)
        else {
            finish(succeeded: false)
            return
        }
        webView.evaluateJavaScript(
            "globalThis.__crestPictureInPicture?.enter(...\(encoded)) ?? false",
            in: candidate.frame, in: BrowserPictureInPictureContentBridge.contentWorld
        ) { [weak self] result in
            guard let self, self.automaticRequest?.id == request.id else { return }
            switch result {
            case .success(let value) where value as? Bool == true: break
            default: self.finish(succeeded: false)
            }
        }
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.automaticPictureInPictureTimeout) } catch { return }
            guard let self, self.automaticRequest?.id == request.id, self.completion != nil else { return }
            self.cancelAutomaticPictureInPicture()
        }
    }

    func cancelAutomaticPictureInPicture() {
        if let request = automaticRequest {
            let id = request.id.uuidString
            webView?.evaluateJavaScript(
                "globalThis.__crestPictureInPicture?.cancel('\(id)'); null",
                in: request.candidate.frame, in: BrowserPictureInPictureContentBridge.contentWorld
            ) { _ in }
        }
        automaticRequest = nil
        finish(succeeded: false)
    }

    private func finish(succeeded: Bool) {
        timeout?.cancel()
        timeout = nil
        let callback = completion
        completion = nil
        automaticRequest = nil
        callback?(succeeded)
    }
}
