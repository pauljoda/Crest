import Foundation

/// The redirect a web auth flow is waiting for, expressed as a URL prefix.
///
/// `identity.launchWebAuthFlow` does not name a scheme; it names a redirect URL
/// that the provider will eventually navigate to, conventionally
/// `https://<extension-id>.chromiumapp.org/…`, and the browser is expected to
/// intercept the first navigation whose URL starts with it. This type carries
/// that prefix and answers the one question the interception needs.
struct BrowserExtensionWebAuthenticationCallback: Equatable, Hashable, Sendable {
    let redirectPrefix: URL

    init(redirectPrefix: URL) {
        self.redirectPrefix = redirectPrefix
    }

    var scheme: String? {
        redirectPrefix.scheme?.lowercased()
    }

    var host: String? {
        redirectPrefix.host()?.lowercased()
    }

    var path: String {
        redirectPrefix.path().isEmpty ? "/" : redirectPrefix.path()
    }

    /// Whether the redirect is an ordinary web URL rather than a custom scheme.
    ///
    /// This is the fork that decides whether `ASWebAuthenticationSession` can
    /// service the flow at all — see
    /// ``BrowserExtensionWebAuthenticationHandling``.
    var usesWebScheme: Bool {
        scheme == "https" || scheme == "http"
    }

    /// Whether `url` is the redirect this flow is waiting for.
    ///
    /// Scheme and host compare case-insensitively, as URL authority components
    /// are defined to; the path is a literal prefix match, so a prefix of `/`
    /// accepts anything on the host.
    func matches(_ url: URL) -> Bool {
        guard let candidateScheme = url.scheme?.lowercased(),
            candidateScheme == scheme
        else {
            return false
        }
        guard url.host()?.lowercased() == host else { return false }
        let candidatePath = url.path().isEmpty ? "/" : url.path()
        return candidatePath.hasPrefix(path)
    }
}
