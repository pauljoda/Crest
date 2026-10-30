import Foundation

/// Where the Apple Passwords vault gets logins and passwords. The helper is
/// the real source; tests stand in a fake.
@MainActor
protocol ApplePasswordsCredentialSource: AnyObject, Sendable {
    /// The usernames saved for the origin's host. Throws unless the origin is
    /// https and the core's answer for the Space allows the helper.
    func logins(
        for origin: CredentialOrigin,
        tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> ApplePasswordsLoginNamesRequest.Logins
    /// The password saved for `username` on the origin's host, under the same rules.
    func password(
        for origin: CredentialOrigin,
        username: String,
        tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String
    /// Whether the helper said it fills one-time codes.
    var canFillOneTimeCodes: Bool { get }
    /// The codes saved for the frame, under the same rules and with the top-level origin beside it.
    func oneTimeCodes(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> [ApplePasswordsOneTimeCode]
    /// The code that is current now for a generated one the person picked.
    func currentOneTimeCode(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, domain: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String
}
