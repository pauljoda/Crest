import Foundation

@MainActor
protocol BrowserCredentialSuggestionLoading: AnyObject {
    /// - Parameter tab: The tab of the page that asked, where there is one.
    func credentialOffer(
        for origin: CredentialOrigin,
        in spaceID: UUID,
        tab: UUID?
    ) async throws -> BrowserCredentialOffer

    /// What a one-time-code field is offered: codes only, never passwords.
    func oneTimeCodeOffer(
        for request: BrowserCredentialFillRequest,
        in spaceID: UUID,
        tab: UUID?
    ) async throws -> BrowserCredentialOffer

    /// Has Apple's Passwords app open on the site. Does nothing unless the
    /// Space uses Apple Passwords and the origin is https.
    func openApplePasswordsApp(for origin: CredentialOrigin, in spaceID: UUID) async

    /// Has Apple Passwords show a pairing code.
    func requestApplePasswordsPairingCode(in spaceID: UUID) async -> BrowserApplePasswordsPairingOutcome

    func completeApplePasswordsPairing(code: String, in spaceID: UUID) async -> BrowserApplePasswordsPairingOutcome

    /// The person dismissed the code entry: tells Apple Passwords to stop waiting for the code.
    func cancelApplePasswordsPairing() async
}
