import Foundation

@MainActor
final class BrowserHTTPAuthenticationSession {
    typealias LoadCredential =
        @MainActor (
            BrowserHTTPAuthenticationProtectionSpace
        ) async throws -> BrowserCredential?

    typealias SaveCredential =
        @MainActor (
            BrowserHTTPAuthenticationSaveRequest
        ) async throws -> Void

    typealias Prompt =
        @MainActor (
            BrowserHTTPAuthenticationPrompt
        ) async -> BrowserHTTPAuthenticationPromptResponse?

    private let loadCredential: LoadCredential
    private let saveCredential: SaveCredential
    private var allowsCredentialSaving: Bool
    let spaceID: UUID
    private var attemptedStoredCredential: BrowserCredential?
    private var attemptedProtectionSpace: BrowserHTTPAuthenticationProtectionSpace?
    private var pendingSaveRequest: BrowserHTTPAuthenticationSaveRequest?

    init(
        spaceID: UUID,
        allowsCredentialSaving: Bool = true,
        loadCredential: @escaping LoadCredential = { _ in nil },
        saveCredential: @escaping SaveCredential = { _ in }
    ) {
        self.spaceID = spaceID
        self.allowsCredentialSaving = allowsCredentialSaving
        self.loadCredential = loadCredential
        self.saveCredential = saveCredential
    }

    func setCredentialStorageEnabled(_ isEnabled: Bool) {
        guard allowsCredentialSaving != isEnabled else { return }
        allowsCredentialSaving = isEnabled
        reset()
    }

    func response(
        to challenge: BrowserAuthenticationChallenge,
        prompt: Prompt
    ) async -> BrowserHTTPAuthenticationDecision {
        await challenge.handling.respond(on: self)(challenge, prompt)
    }

    func authenticationSucceeded() async {
        guard let pendingSaveRequest else {
            reset()
            return
        }
        self.pendingSaveRequest = nil
        try? await saveCredential(pendingSaveRequest)
        reset()
    }

    func authenticationFailed() {
        reset()
    }

    private func passwordResponse(
        to challenge: BrowserAuthenticationChallenge,
        prompt: Prompt
    ) async -> BrowserHTTPAuthenticationDecision {
        guard let protectionSpace = challenge.protectionSpace else {
            return .performDefaultHandling
        }

        let isSecureOrigin = protectionSpace.origin.isSecure
        let stored: BrowserCredential? =
            if allowsCredentialSaving, challenge.previousFailureCount == 0, isSecureOrigin {
                try? await loadCredential(protectionSpace)
            } else {
                nil
            }
        let attemptedSameProtectionSpace = attemptedProtectionSpace == protectionSpace
        let plan = try? CrestCore.answer(
            HttpAuthenticationChallengePlan(
                allowsCredentialSaving: allowsCredentialSaving,
                isSecureOrigin: isSecureOrigin,
                previousFailureCount: challenge.previousFailureCount,
                hasStoredCredential: stored != nil,
                attemptedSameProtectionSpace: attemptedSameProtectionSpace,
                proposedUsername: challenge.proposedUsername,
                attemptedUsername: attemptedStoredCredential?.descriptor.username
            ))
        guard let plan else {
            authenticationFailed()
            return .cancel
        }

        let rejectedCredential: BrowserCredential?
        if plan.storedCredentialRejected {
            rejectedCredential = attemptedStoredCredential
            reset()
        } else {
            rejectedCredential = nil
        }

        if plan.usesStoredCredential, let stored {
            attemptedStoredCredential = stored
            attemptedProtectionSpace = protectionSpace
            pendingSaveRequest = BrowserHTTPAuthenticationSaveRequest(
                protectionSpace: protectionSpace,
                username: stored.descriptor.username,
                password: stored.password,
                replacing: stored.descriptor
            )
            return credentialResolution(
                username: stored.descriptor.username,
                password: stored.password
            )
        }

        let response = await prompt(
            BrowserHTTPAuthenticationPrompt(
                descriptor: challenge.descriptor,
                suggestedUsername: plan.suggestedUsername,
                allowsSaving: plan.allowsSaving
            )
        )
        guard let response else {
            authenticationFailed()
            return .cancel
        }

        let saveDecision = try? CrestCore.answer(
            HttpAuthenticationSavePlan(
                allowsCredentialSaving: allowsCredentialSaving,
                isSecureOrigin: isSecureOrigin,
                userRequestedSave: response.shouldSave,
                submittedUsername: response.username,
                rejectedUsername: rejectedCredential?.descriptor.username
            ))
        if saveDecision?.shouldSave == true {
            pendingSaveRequest = BrowserHTTPAuthenticationSaveRequest(
                protectionSpace: protectionSpace,
                username: response.username,
                password: response.password,
                replacing: saveDecision?.replacesRejectedCredential == true ? rejectedCredential?.descriptor : nil
            )
        } else {
            pendingSaveRequest = nil
        }
        attemptedStoredCredential = nil
        attemptedProtectionSpace = nil
        return credentialResolution(
            username: response.username,
            password: response.password
        )
    }

    private func credentialResolution(
        username: String,
        password: String
    ) -> BrowserHTTPAuthenticationDecision {
        .useCredential(username: username, password: password)
    }

    private func reset() {
        attemptedStoredCredential = nil
        attemptedProtectionSpace = nil
        pendingSaveRequest = nil
    }
}

// MARK: - Actions - Responding

extension BrowserHTTPAuthenticationSession: AuthenticationResponder {
    /// The session's answer to a challenge, which it finishes with the
    /// challenge and the prompt that may ask the person.
    typealias Response =
        @MainActor (BrowserAuthenticationChallenge, Prompt) async -> BrowserHTTPAuthenticationDecision

    func performDefaultHandling() -> Response {
        { _, _ in .performDefaultHandling }
    }

    func cancelChallenge() -> Response {
        { [self] _, _ in
            authenticationFailed()
            return .cancel
        }
    }

    func promptForCredentials() -> Response {
        { [self] challenge, prompt in
            await passwordResponse(to: challenge, prompt: prompt)
        }
    }
}
