import Foundation

/// Chrome's own `chrome.identity` failure text, reproduced exactly.
///
/// Extensions branch on these strings. The Claude package treats "User
/// interaction required." as "the silent refresh failed, show the sign-in
/// button" and anything else as a transport fault worth retrying, so
/// paraphrasing them changes behaviour rather than wording.
///
/// None of these carry the flow's URL. The authorize URL holds the PKCE
/// challenge and the account hint, and the redirect URL holds the
/// authorization code; an error message is a place a package logs, so nothing
/// that identifies the flow appears in one.
enum BrowserExtensionIdentityBrokerError: LocalizedError, Equatable {
    /// The navigation failed, or Crest has no window, data store, or host to
    /// run the flow in. Chrome reports every unreachable authorization page
    /// the same way.
    case pageLoadFailure
    /// An interactive window the person closed without approving.
    case userRejected
    /// A non-interactive flow that would have needed the person to act:
    /// the page finished loading without redirecting, or the timeout expired.
    case interactionRequired
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .pageLoadFailure: "Authorization page could not be loaded."
        case .userRejected: "The user did not approve access."
        case .interactionRequired: "User interaction required."
        case .invalidRequest: "The extension supplied an invalid identity request."
        }
    }
}

/// The wire request behind `chrome.identity.launchWebAuthFlow`.
///
/// The extension names the authorization URL and the flow's shape; it never
/// names the redirect it expects. Crest derives that from the loaded context's
/// own base URL, so a package cannot ask Crest to hand it a URL — and the code
/// in its query — from an origin it does not own.
///
/// `timeoutMs` is clamped here rather than trusted: Chrome caps a
/// non-interactive flow at 60 seconds, and a request asking for longer is a
/// request to keep an invisible web view alive indefinitely.
struct BrowserExtensionIdentityBrokerRequest: Equatable {
    static let api = "identity.launchWebAuthFlow"

    /// Chrome's ceiling and default for `timeoutMsForNonInteractive`.
    static let maximumNonInteractiveTimeout: TimeInterval = 60

    let url: URL
    let isInteractive: Bool
    let abortsOnLoadForNonInteractive: Bool
    let nonInteractiveTimeout: TimeInterval

    init(message: [String: Any]) throws {
        guard (message["api"] as? String) == Self.api else {
            throw BrowserExtensionIdentityBrokerError.invalidRequest
        }
        guard let raw = message["url"] as? String,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host?.isEmpty == false
        else {
            throw BrowserExtensionIdentityBrokerError.invalidRequest
        }
        self.url = url
        isInteractive = message["interactive"] as? Bool ?? false
        abortsOnLoadForNonInteractive =
            message["abortOnLoadForNonInteractive"] as? Bool ?? true
        let requested = (message["timeoutMs"] as? NSNumber)?.doubleValue
        let seconds = (requested ?? Self.maximumNonInteractiveTimeout * 1000) / 1000
        guard seconds.isFinite, seconds > 0 else {
            throw BrowserExtensionIdentityBrokerError.invalidRequest
        }
        nonInteractiveTimeout = min(seconds, Self.maximumNonInteractiveTimeout)
    }
}

/// The origin Chrome watches for, derived from the extension's own runtime id.
///
/// Chrome does not own `chromiumapp.org` and neither does Crest. Both watch
/// their own web view for the first navigation to
/// `https://<runtime id>.chromiumapp.org` and cancel it, so the redirect never
/// reaches the network and the code never leaves the browser.
///
/// A verified Chrome Web Store package runs at its real store origin, so this
/// is the `[a-p]{32}` host the provider already has on file. Every other
/// package keeps Crest's per-Space host, which is not a Chrome-shaped id — the
/// origin is still watched and still honoured, but a provider that validates
/// the redirect host will refuse the flow, exactly as it refuses an unpacked
/// extension in Chrome.
enum BrowserExtensionIdentityRedirectOrigin {
    static let host = "chromiumapp.org"

    static func origin(runtimeID: String) -> String? {
        guard !runtimeID.isEmpty,
            runtimeID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { return nil }
        return "https://\(runtimeID.lowercased()).\(host)"
    }

    /// Whether `url` is the redirect this flow is waiting for.
    ///
    /// Origin equality, not a prefix test: Chrome matches
    /// `https://<id>.chromiumapp.org/*`, so any path, query, or fragment
    /// completes the flow while a look-alike host such as
    /// `<id>.chromiumapp.org.example.com` does not.
    static func matches(_ url: URL, origin: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(),
            components.port == nil
        else { return false }
        return "\(scheme)://\(host)" == origin.lowercased()
    }
}
