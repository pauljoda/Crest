import Foundation

/// Reconciles the URL an extension reports for a tab with the URL Crest holds
/// for it.
///
/// WebKit serializes tab URLs the WHATWG way, so a root URL reaches the
/// extension as `https://apple.com/`, while Crest's session stores the same
/// tab as `https://apple.com`. Both name one tab. The comparison therefore
/// normalizes the parts that differ only by serialization — the root path and
/// the case of scheme and host — and nothing else: a different path, query,
/// fragment or origin is still a different tab.
enum BrowserExtensionTabIdentity {
    static func urlMatches(reported: String?, state: URL?) -> Bool {
        guard let reported else { return true }
        guard let state else { return false }
        return normalized(reported) == normalized(state.absoluteString)
    }

    private static func normalized(_ string: String) -> String {
        guard var components = URLComponents(string: string) else { return string }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.isEmpty, components.host != nil { components.path = "/" }
        return components.string ?? string
    }
}
