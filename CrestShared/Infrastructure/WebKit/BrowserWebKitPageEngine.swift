import Foundation
import Observation
import WebKit

/// The same WebKit port serves desktop and mobile. Supplemental same-document
/// history stays with its engine rather than leaking WKBackForwardListItem to UI.
@Observable @MainActor
final class BrowserWebKitPageEngine: BrowserPageEngine {
    let registration = BrowserEngineRegistration.webKit
    let webView: WKWebView
    var history = BrowserPageNavigationHistory()
    var nativeView: BrowserEngineView { webView }
    /// WebKit reports its native video presentation only to the UI delegate,
    /// which covers PiP entered from its own controls and cross-origin frames.
    /// The page that owns the delegate forwards the callback here.
    @ObservationIgnored var hasVideoInPictureInPicture = false
    @ObservationIgnored private var stagedRequest: URLRequest?
    #if os(macOS)
        @ObservationIgnored private var closeCompletion: (@MainActor (Bool) -> Void)?
        @ObservationIgnored private var closeTimeout: Task<Void, Never>?
    #endif

    init(webView: WKWebView) { self.webView = webView }

    private struct StagedLink {
        let request: URLRequest
        weak var dataStore: WKWebsiteDataStore?
        let stagedAt: Date
    }
    private static var stagedLinks: [String: StagedLink] = [:]

    /// Holds a modified link's request under a one-shot token, so the page Crest
    /// opens for it replays the initiator's referrer instead of a bare URL.
    /// Only a plain GET is staged: WebKit has no public way to hand another view
    /// a form body, the initiating origin, user activation or sandbox flags.
    static func stageLink(_ request: URLRequest, from webView: WKWebView) -> BrowserEngineNavigation? {
        guard let url = request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            (request.httpMethod ?? "GET").uppercased() == "GET",
            request.httpBody == nil, request.httpBodyStream == nil
        else { return nil }
        let now = Date()
        stagedLinks = stagedLinks.filter {
            $0.value.dataStore != nil && now.timeIntervalSince($0.value.stagedAt) < 300
        }
        if stagedLinks.count >= 16,
            let oldest = stagedLinks.min(by: { $0.value.stagedAt < $1.value.stagedAt })?.key
        {
            stagedLinks[oldest] = nil
        }
        var replay = URLRequest(url: url, cachePolicy: request.cachePolicy)
        if let referrer = request.value(forHTTPHeaderField: "Referer") {
            replay.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        let token = UUID().uuidString
        stagedLinks[token] = StagedLink(
            request: replay,
            dataStore: webView.configuration.websiteDataStore, stagedAt: now)
        return BrowserEngineNavigation(
            implementation: BrowserEngineRegistration.webKit.implementationId,
            token: token)
    }

    /// Consumes the token even when it is refused, and only for a page that has
    /// not loaded yet in the same website data store as the link's source.
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool {
        guard navigation.implementation == registration.implementationId,
            let staged = Self.stagedLinks.removeValue(forKey: navigation.token),
            stagedRequest == nil, webView.url == nil,
            staged.request.url == url,
            staged.dataStore === webView.configuration.websiteDataStore
        else { return false }
        stagedRequest = staged.request
        return true
    }

    var interactionState: Data? {
        guard webView.backForwardList.currentItem != nil,
            let state = webView.interactionState as? Data
        else { return nil }
        return BrowserEngineInteractionState(
            engine: .webKit,
            version: BrowserTabStateEnvelope.currentOSBuild, payload: state
        ).encoded()
    }

    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        // Supplements describe the list being replaced.
        history = BrowserPageNavigationHistory()
        guard
            let payload = BrowserEngineInteractionState.payload(
                state, engine: .webKit,
                version: BrowserTabStateEnvelope.currentOSBuild)
        else { return false }
        webView.interactionState = payload
        return webView.backForwardList.currentItem != nil
    }

    var currentURL: URL? { webView.url }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }

    @discardableResult
    func synchronizeHistory() -> URL? {
        history.synchronize(with: webView.backForwardList)
        return webView.backForwardList.currentItem?.url
    }

    /// WebKit has no popup blocker to tell; the page's preferences carry it.
    func applyAutomaticPopups(_ allowed: Bool) -> Bool {
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowed
        return true
    }

    /// WebKit leaves capture running after Crest withdraws a grant; Crest's
    /// own prompt decided it, so Crest ends it.
    func stopMediaCapture(_ media: SitePermission) {
        if media.devices.contains(.camera) { webView.setCameraCaptureState(.none, completionHandler: nil) }
        if media.devices.contains(.microphone) { webView.setMicrophoneCaptureState(.none, completionHandler: nil) }
    }

    func evaluateInMainFrame(_ body: String) async -> Any? {
        try? await webView.callAsyncJavaScript(body, arguments: [:], contentWorld: .defaultClient)
    }

    func clearSiteData(for url: URL) async -> Bool {
        await BrowserWebsiteDataStore.clearSiteData(for: url, in: webView.configuration.websiteDataStore)
        return true
    }

    var backHistory: [BrowserNavigationHistoryItem] {
        history.backItems.reversed().enumerated().map { Self.item($0.element, depth: $0.offset + 1) }
    }
    var forwardHistory: [BrowserNavigationHistoryItem] {
        history.forwardItems.enumerated().map { Self.item($0.element, depth: $0.offset + 1) }
    }
    func load(_ request: URLRequest) {
        if let staged = stagedRequest {
            stagedRequest = nil
            if staged.url == request.url {
                webView.load(staged)
                return
            }
        }
        // A local document needs an explicit read-access root before WebKit will
        // give the document its own file origin; an ordinary request would load
        // the page without its stylesheets, scripts or images. The folder holding
        // the file is that root, which is what a saved page's resources sit in.
        if let url = request.url, BrowserCorePolicy.acceptsLocalDocument(url) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }
        webView.load(request)
    }
    func navigateHistory(by offset: Int) {
        guard offset != 0 else { return }
        history.synchronize(with: webView.backForwardList)
        let items = offset < 0 ? history.backItems : history.forwardItems
        let index = offset < 0 ? items.count + offset : offset - 1
        if items.indices.contains(index) {
            webView.go(to: items[index])
        } else if offset == -1 {
            webView.goBack()
        } else if offset == 1 {
            webView.goForward()
        }
    }
    func reload(bypassingCache: Bool) {
        if bypassingCache { webView.reloadFromOrigin() } else { webView.reload() }
    }
    func stop() { webView.stopLoading() }
    func setZoom(_ zoom: CGFloat) { webView.pageZoom = zoom }
    func performFind(
        _ query: String, configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (BrowserFindResult) -> Void
    ) {
        webView.performFind(query, configuration: configuration, completion: completion)
    }
    private static func item(_ item: WKBackForwardListItem, depth: Int) -> BrowserNavigationHistoryItem {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BrowserNavigationHistoryItem(
            depth: depth,
            title: title.isEmpty ? item.url.host() ?? item.url.absoluteString : title, url: item.url)
    }
    func mediaActivity() async -> BrowserPageMediaActivity? {
        let state = await withCheckedContinuation { continuation in
            webView.requestMediaPlaybackState { continuation.resume(returning: $0) }
        }
        return BrowserPageMediaActivity(
            isPlaying: state == .playing,
            isCapturing: webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none,
            hasPictureInPicture: hasVideoInPictureInPicture)
    }
    #if os(macOS)
        /// Asks the page's beforeunload handlers whether it may close. WebKit runs
        /// them for an embedder close only through `_tryClose`, which answers
        /// immediately when no document in the process needs the event, and
        /// otherwise ends in `webViewDidClose` or a beforeunload panel the person
        /// can decline. Approval leaves the page alive; the caller releases it.
        func prepareToClose(completion: @escaping @MainActor (Bool) -> Void) {
            let selector = NSSelectorFromString("_tryClose")
            guard closeCompletion == nil else {
                completion(false)
                return
            }
            guard webView.responds(to: selector) else {
                completion(true)
                return
            }
            typealias TryClose = @convention(c) (AnyObject, Selector) -> Bool
            let tryClose = unsafeBitCast(webView.method(for: selector), to: TryClose.self)
            if tryClose(webView, selector) {
                completion(true)
                return
            }
            closeCompletion = completion
            scheduleCloseTimeout()
        }

        /// True when a close this port requested owns the panel being shown.
        var isPreparingToClose: Bool { closeCompletion != nil }

        /// The person is deciding; a prompt has no time limit.
        func beforeUnloadPanelWillAppear() { closeTimeout?.cancel() }

        /// Staying ends the close here: WebKit sends nothing more. Leaving still
        /// waits for WebKit's close callback.
        func beforeUnloadPanelDidFinish(leaving: Bool) {
            guard closeCompletion != nil else { return }
            if leaving { scheduleCloseTimeout() } else { finishClose(false) }
        }

        /// Returns true when the callback answers this port's own close request,
        /// so it must not be treated as the page calling `window.close()`.
        func webViewDidClose() -> Bool {
            guard closeCompletion != nil else { return false }
            finishClose(true)
            return true
        }

        // WebKit already closes after its own short timeout when the web process
        // does not answer; this only guards against a callback that never comes.
        private func scheduleCloseTimeout() {
            closeTimeout?.cancel()
            closeTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.finishClose(true)
            }
        }

        private func finishClose(_ allowed: Bool) {
            closeTimeout?.cancel()
            closeTimeout = nil
            let completion = closeCompletion
            closeCompletion = nil
            completion?(allowed)
        }

        func showInspector() -> Bool {
            BrowserWebInspectorAccess.show(inspectorOwner: webView, isInspectable: webView.isInspectable)
        }
        func toggleInspector(_ panel: BrowserDeveloperPanel, current: BrowserDeveloperPanel?)
            -> BrowserWebInspectorToggleResult
        {
            BrowserWebInspectorAccess.toggle(
                panel, currentPanel: current,
                inspectorOwner: webView, isInspectable: webView.isInspectable)
        }
        // WKWebView travels with the retained page; its lifetime is not owned by an NSWindow.
        func transferOwnership(to windowID: BrowserWindowID) -> Bool { true }

        func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void) {
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = false
            if let rect { configuration.rect = rect }
            if let width { configuration.snapshotWidth = NSNumber(value: Double(width)) }
            webView.takeSnapshot(with: configuration) { image, _ in
                MainActor.assumeIsolated { completion(image) }
            }
        }
    #endif

}

#if os(macOS)
    extension BrowserWebKitPageEngine: BrowserPageDocumentServices {
        var documentServices: (any BrowserPageDocumentServices)? { self }
        var archiveFormat: BrowserPageArchiveFormat { .webKit }

        func fullPageSnapshot(width snapshotWidth: CGFloat?) async throws -> NSImage {
            let result = try await webView.evaluateJavaScript(
                """
                (() => {
                  const root = document.documentElement;
                  const body = document.body;
                  return [
                    Math.max(root?.scrollWidth ?? 0, body?.scrollWidth ?? 0, innerWidth),
                    Math.max(root?.scrollHeight ?? 0, body?.scrollHeight ?? 0, innerHeight)
                  ];
                })()
                """
            )
            guard let dimensions = result as? [NSNumber],
                dimensions.count == 2
            else {
                throw BrowserDeveloperCaptureError.dimensionsUnavailable
            }

            let width = min(
                max(CGFloat(dimensions[0].doubleValue), webView.bounds.width),
                6_000
            )
            let height = min(
                max(CGFloat(dimensions[1].doubleValue), webView.bounds.height),
                24_000
            )
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
            configuration.afterScreenUpdates = true
            let desiredWidth = snapshotWidth ?? min(width, 1_600)
            configuration.snapshotWidth = NSNumber(value: Double(desiredWidth))
            return try await webView.takeSnapshot(configuration: configuration)
        }
        func pdfData() async throws -> Data { try await webView.pdf(configuration: WKPDFConfiguration()) }
        func webArchiveData() async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                webView.createWebArchiveData { continuation.resume(with: $0) }
            }
        }
        func printOperation(with info: NSPrintInfo) async throws -> NSPrintOperation {
            webView.printOperation(with: info)
        }
    }
#endif
