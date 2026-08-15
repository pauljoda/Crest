import Foundation

/// The port backing Crest's emulated `identity.launchWebAuthFlow`.
///
/// ## The redirect constraint
///
/// Chrome extensions almost always pass a redirect URL of the form
/// `https://<extension-id>.chromiumapp.org/*`. Chrome does not own that domain
/// either — it simply watches its own web view and intercepts the first
/// navigation that starts with the expected prefix.
///
/// `ASWebAuthenticationSession` cannot reproduce that. Its callback is declared
/// up front and comes in two shapes:
///
/// - `.customScheme(_:)` matches a custom URL scheme. This works with no extra
///   configuration and is what Crest uses whenever the extension supplies one.
/// - `.https(host:path:)` (macOS 14.4+) matches a real web URL, but only for a
///   host the app is *associated* with: the app needs an
///   `com.apple.developer.associated-domains` entitlement naming
///   `webcredentials:<host>`, **and** that host must serve an
///   `apple-app-site-association` file listing Crest's bundle identifier. The
///   system refuses to start a session whose callback host fails that check.
///
/// Crest controls neither `chromiumapp.org` nor the association file Google
/// would have to publish for it, so an `https` redirect on an unassociated host
/// is rejected with
/// ``BrowserExtensionWebAuthenticationError/unsupportedCallback`` rather than
/// started and left to hang. Supporting those flows properly needs a
/// Crest-owned authentication window that watches navigation the way Chrome
/// does; that is deliberately not attempted here, and the adapter is
/// constructed with the set of hosts Crest genuinely is associated with so the
/// supported cases keep working.
@MainActor
protocol BrowserExtensionWebAuthenticationHandling: AnyObject {
    /// Runs the flow and returns the redirect URL it ended on.
    ///
    /// Throws ``BrowserExtensionWebAuthenticationError``.
    func launch(_ request: BrowserExtensionWebAuthenticationRequest) async throws -> URL
}
