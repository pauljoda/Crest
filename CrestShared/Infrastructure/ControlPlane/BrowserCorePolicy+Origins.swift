import Foundation

/// External scheme, link and local-file rules answered by the portable core.
/// URLs cross as the facts Foundation's parser reports, so the core judges the
/// same parse the engine loads. Every answer fails closed: a link or document
/// that cannot be evaluated is refused, and a scheme is blocked.
extension BrowserCorePolicy {
    /// Whether another application, a drop, a peek, a popup or a menu item may
    /// hand Crest this URL as a web link: HTTP or HTTPS with a host.
    static func acceptsExternalURL(_ url: URL) -> Bool {
        evaluate(["version": 1, "operation": "external.url",
            "scheme": nonEmpty(url.scheme), "host": nonEmpty(url.host(percentEncoded: false))])?["accepted"] as? Bool ?? false
    }

    /// Whether Crest opens this URL as a local document. Only document-open
    /// routes ask; a web link never reaches a local path through this.
    static func acceptsLocalDocument(_ url: URL) -> Bool {
        evaluate(["version": 1, "operation": "external.local_document", "isFile": url.isFileURL,
            "hasUser": url.user() != nil, "hasPath": !url.path().isEmpty,
            "host": nonEmpty(url.host(percentEncoded: false))])?["accepted"] as? Bool ?? false
    }

    /// Which engine, if any, owns a navigation once its scheme is known. Only
    /// a load Crest itself initiated may keep `file:`.
    static func externalSchemeDisposition(for url: URL?, isAppInitiated: Bool = false) -> BrowserExternalSchemeDisposition {
        switch evaluate(["version": 1, "operation": "external.scheme", "scheme": nonEmpty(url?.scheme),
            "appInitiated": isAppInitiated])?["disposition"] as? String {
        case "engine": return .webKit
        case "handOff": return .handOff
        default: return .blocked
        }
    }

    /// What one external-app hand-off does once its saved choice is known.
    static func externalSchemeConsent(decision: BrowserSitePermissionDecision) -> BrowserExternalSchemeConsent {
        switch evaluate(["version": 1, "operation": "external.consent", "decision": decision.rawValue])?["consent"] as? String {
        case "open": return .open
        case "prompt": return .prompt
        default: return .block
        }
    }

    static func nonEmpty(_ value: String?) -> Any {
        guard let value, !value.isEmpty else { return NSNull() }
        return value
    }
}
