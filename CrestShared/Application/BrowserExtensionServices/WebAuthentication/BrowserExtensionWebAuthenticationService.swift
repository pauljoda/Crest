import Foundation

/// Guards and validates emulated `identity.launchWebAuthFlow` calls around the
/// system authentication session.
///
/// Two checks bracket the session, and both matter: a callback the system
/// cannot service is refused before a window ever appears, and a redirect the
/// system does return is re-checked against the prefix the extension actually
/// asked for. The second check is not redundant — it keeps a provider that
/// redirects somewhere unexpected from handing an extension a URL (and any
/// token in its fragment) it never requested.
@MainActor
final class BrowserExtensionWebAuthenticationService:
    BrowserExtensionWebAuthenticationHandling
{
    private let session: any BrowserExtensionWebAuthenticationSessionStarting
    private let associatedWebCredentialHosts: Set<String>

    /// - Parameter associatedWebCredentialHosts: Hosts Crest carries a
    ///   `webcredentials:` associated domain for. Only these may be used with
    ///   an `https` redirect; everything else is rejected as unsupported.
    init(
        session: any BrowserExtensionWebAuthenticationSessionStarting,
        associatedWebCredentialHosts: Set<String> = []
    ) {
        self.session = session
        self.associatedWebCredentialHosts = Set(
            associatedWebCredentialHosts.map { $0.lowercased() }
        )
    }

    func launch(
        _ request: BrowserExtensionWebAuthenticationRequest
    ) async throws -> URL {
        guard canService(request.callback) else {
            throw BrowserExtensionWebAuthenticationError.unsupportedCallback
        }

        let redirectURL = try await session.start(
            authorizationURL: request.authorizationURL,
            callback: request.callback,
            prefersEphemeralSession: request.prefersEphemeralSession
        )

        guard request.callback.matches(redirectURL) else {
            throw BrowserExtensionWebAuthenticationError.invalidCallback
        }
        return redirectURL
    }

    /// Whether the system authentication session can watch for this redirect.
    func canService(
        _ callback: BrowserExtensionWebAuthenticationCallback
    ) -> Bool {
        guard callback.usesWebScheme else {
            // A custom scheme needs no association; the system matches it
            // directly.
            return callback.scheme?.isEmpty == false
        }
        guard callback.scheme == "https", let host = callback.host else {
            // Plain http is never a valid associated-domain callback.
            return false
        }
        return associatedWebCredentialHosts.contains(host)
    }
}
