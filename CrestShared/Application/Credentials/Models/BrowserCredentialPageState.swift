import Foundation
import Observation

/// Owns the short-lived credential state for one retained browser page.
///
/// The generic fill target is intentionally opaque here. WebKit pages use a
/// `WKFrameInfo`, while tests can use a harmless value. The immutable Space ID
/// prevents a prompt from following the app's currently selected Space.
@Observable
@MainActor
final class BrowserCredentialPageState<FillTarget> {
    let spaceID: SpaceID

    private(set) var fillRequest: BrowserCredentialFillRequest?
    private(set) var saveCandidate: BrowserCredentialSaveCandidate?

    @ObservationIgnored private var fillTargets: [UUID: FillTarget] = [:]
    @ObservationIgnored private var pendingUsernameHint: BrowserCredentialUsernameHint?
    @ObservationIgnored private var usernameExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveCandidate: BrowserCredentialSaveCandidate?
    @ObservationIgnored private var candidateExpirationTask: Task<Void, Never>?

    init(spaceID: SpaceID) {
        self.spaceID = spaceID
    }

    func receive(
        _ message: BrowserCredentialFormMessage,
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        isMainFrame: Bool,
        fillTarget: FillTarget?
    ) {
        switch message.event {
        case .username:
            guard
                BrowserCredentialCapturePolicy.accepts(
                    frameOrigin: frameOrigin,
                    topLevelOrigin: topLevelOrigin
                ), let username = message.username
            else {
                return
            }
            rememberUsername(username, origin: frameOrigin, topLevelOrigin: topLevelOrigin)

        case .focus:
            guard let passwordKind = message.passwordKind else {
                dismissFillRequest()
                return
            }
            guard
                BrowserCredentialCapturePolicy.accepts(
                    frameOrigin: frameOrigin,
                    topLevelOrigin: topLevelOrigin
                ), message.formID != nil,
                let fillTarget
            else {
                return
            }

            let request = BrowserCredentialFillRequest(
                id: UUID(),
                origin: frameOrigin,
                topLevelOrigin: topLevelOrigin,
                usernameHint: resolvedUsername(
                    explicitUsername: message.username,
                    origin: frameOrigin,
                    topLevelOrigin: topLevelOrigin
                ),
                passwordKind: passwordKind,
                isCrossOriginFrame: frameOrigin != topLevelOrigin,
                requestedAt: .now
            )
            if let previousRequest = fillRequest {
                fillTargets[previousRequest.id] = nil
            }
            fillTargets[request.id] = fillTarget
            fillRequest = request

        case .submit:
            guard
                BrowserCredentialCapturePolicy.accepts(
                    frameOrigin: frameOrigin,
                    topLevelOrigin: topLevelOrigin
                ),
                let username = resolvedUsername(
                    explicitUsername: message.username,
                    origin: frameOrigin,
                    topLevelOrigin: topLevelOrigin
                ), let password = message.password,
                let passwordKind = message.passwordKind
            else {
                return
            }

            dismissSaveCandidate()
            let candidate = BrowserCredentialSaveCandidate(
                id: UUID(),
                origin: frameOrigin,
                topLevelOrigin: topLevelOrigin,
                username: username,
                password: password,
                passwordKind: passwordKind,
                isCrossOriginFrame: frameOrigin != topLevelOrigin,
                submittedAt: .now
            )
            dismissFillRequest()
            clearUsernameHint()
            pendingSaveCandidate = candidate
            candidateExpirationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(BrowserCredentialCapturePolicy.candidateLifetime))
                guard !Task.isCancelled, let self else { return }
                if self.pendingSaveCandidate?.id == candidate.id {
                    self.pendingSaveCandidate = nil
                }
                if self.saveCandidate?.id == candidate.id {
                    self.saveCandidate = nil
                }
                self.candidateExpirationTask = nil
            }

        case .documentState:
            guard let candidate = pendingSaveCandidate,
                let hasVisiblePasswordField = message.hasVisiblePasswordField,
                isMainFrame || frameOrigin == candidate.origin
            else {
                return
            }
            guard
                BrowserCredentialCapturePolicy.shouldOfferSave(
                    candidate: candidate,
                    hasVisiblePasswordField: hasVisiblePasswordField
                )
            else {
                if Date.now.timeIntervalSince(candidate.submittedAt)
                    > BrowserCredentialCapturePolicy.candidateLifetime
                {
                    pendingSaveCandidate = nil
                }
                return
            }
            pendingSaveCandidate = nil
            saveCandidate = candidate
        }
    }

    func fillContext(
        for requestID: UUID,
        credential: BrowserCredential
    ) throws -> (request: BrowserCredentialFillRequest, target: FillTarget) {
        guard let request = fillRequest,
            request.id == requestID,
            BrowserCredentialCapturePolicy.offersSavedCredentials(
                for: request.passwordKind
            ),
            credential.descriptor.spaceID == spaceID,
            credential.descriptor.origin == request.origin,
            let target = fillTargets[requestID]
        else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        return (request, target)
    }

    func generatedPasswordFillContext(
        for requestID: UUID
    ) throws -> (request: BrowserCredentialFillRequest, target: FillTarget) {
        guard let request = fillRequest,
            request.id == requestID,
            request.passwordKind == .new,
            let target = fillTargets[requestID]
        else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        return (request, target)
    }

    func completeFill(username: String, requestID: UUID) {
        guard let request = fillRequest, request.id == requestID else { return }
        rememberUsername(username, origin: request.origin, topLevelOrigin: request.topLevelOrigin)
        dismissFillRequest()
    }

    func completeGeneratedPasswordFill(requestID: UUID) {
        guard fillRequest?.id == requestID else { return }
        dismissFillRequest()
    }

    func dismissFillRequest() {
        guard let request = fillRequest else { return }
        fillTargets[request.id] = nil
        fillRequest = nil
    }

    func dismissSaveCandidate() {
        pendingSaveCandidate = nil
        candidateExpirationTask?.cancel()
        candidateExpirationTask = nil
        saveCandidate = nil
    }

    func didChangeTopLevelURL(to url: URL?) {
        guard let hint = pendingUsernameHint,
            let url,
            let currentOrigin = CredentialOrigin(url: url),
            currentOrigin != hint.topLevelOrigin
        else { return }
        clearUsernameHint()
    }

    func didStartNavigation() {
        dismissFillRequest()
    }

    func webContentProcessDidTerminate() {
        reset()
    }

    func reset() {
        dismissFillRequest()
        dismissSaveCandidate()
        clearUsernameHint()
    }

    private func rememberUsername(
        _ username: String,
        origin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin
    ) {
        let hint = BrowserCredentialUsernameHint(
            origin: origin,
            topLevelOrigin: topLevelOrigin,
            username: username,
            capturedAt: .now
        )
        pendingUsernameHint = hint
        usernameExpirationTask?.cancel()
        usernameExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BrowserCredentialCapturePolicy.usernameHintLifetime))
            guard !Task.isCancelled,
                self?.pendingUsernameHint?.capturedAt == hint.capturedAt
            else { return }
            self?.pendingUsernameHint = nil
            self?.usernameExpirationTask = nil
        }
    }

    private func resolvedUsername(
        explicitUsername: String?,
        origin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin
    ) -> String? {
        if let explicitUsername { return explicitUsername }
        guard let hint = pendingUsernameHint,
            let username = BrowserCredentialCapturePolicy.username(
                from: hint,
                frameOrigin: origin,
                topLevelOrigin: topLevelOrigin
            )
        else {
            clearUsernameHint()
            return nil
        }
        return username
    }

    private func clearUsernameHint() {
        usernameExpirationTask?.cancel()
        usernameExpirationTask = nil
        pendingUsernameHint = nil
    }
}
