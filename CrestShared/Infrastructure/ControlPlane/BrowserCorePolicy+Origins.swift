import Foundation

/// External scheme, link and local-file rules answered by the portable core.
/// URLs cross as the facts Foundation's parser reports, so the core judges the
/// same parse the engine loads. Every answer fails closed: a link or document
/// that cannot be evaluated is refused, and a scheme is blocked.
extension BrowserCorePolicy {
    // MARK: - Types

    private struct ExternalURLRequest: Encodable {
        @BrowserCoreNullable var scheme: String?
        @BrowserCoreNullable var host: String?
    }

    private struct LocalDocumentRequest: Encodable {
        let isFile: Bool
        let hasUser: Bool
        let hasPath: Bool
        @BrowserCoreNullable var host: String?
    }

    private struct AcceptedAnswer: Decodable {
        @BrowserCoreOptional var accepted: Bool?
    }

    private struct SchemeRequest: Encodable {
        @BrowserCoreNullable var scheme: String?
        let appInitiated: Bool
    }

    private struct SchemeAnswer: Decodable {
        /// The core's disposition spellings; any other answer blocks.
        enum Disposition: String, Decodable {
            case engine
            case handOff
        }

        @BrowserCoreOptional var disposition: Disposition?
    }

    private struct ConsentRequest: Encodable {
        let decision: BrowserSitePermissionDecision
    }

    private struct ConsentAnswer: Decodable {
        @BrowserCoreOptional var consent: BrowserExternalSchemeConsent?
    }

    // MARK: - Actions - Origins

    /// Whether another application, a drop, a peek, a popup or a menu item may
    /// hand Crest this URL as a web link: HTTP or HTTPS with a host.
    static func acceptsExternalURL(_ url: URL) -> Bool {
        let request = ExternalURLRequest(scheme: nonEmpty(url.scheme), host: nonEmpty(url.host(percentEncoded: false)))
        return evaluate(.externalURL, request, answer: AcceptedAnswer.self)?.accepted ?? false
    }

    /// Whether Crest opens this URL as a local document. Only document-open
    /// routes ask; a web link never reaches a local path through this.
    static func acceptsLocalDocument(_ url: URL) -> Bool {
        let request = LocalDocumentRequest(
            isFile: url.isFileURL, hasUser: url.user() != nil, hasPath: !url.path().isEmpty,
            host: nonEmpty(url.host(percentEncoded: false)))
        return evaluate(.externalLocalDocument, request, answer: AcceptedAnswer.self)?.accepted ?? false
    }

    /// Which engine, if any, owns a navigation once its scheme is known. Only
    /// a load Crest itself initiated may keep `file:`.
    static func externalSchemeDisposition(for url: URL?, isAppInitiated: Bool = false)
        -> BrowserExternalSchemeDisposition
    {
        let request = SchemeRequest(scheme: nonEmpty(url?.scheme), appInitiated: isAppInitiated)
        switch evaluate(.externalScheme, request, answer: SchemeAnswer.self)?.disposition {
        case .engine: return .webKit
        case .handOff: return .handOff
        case nil: return .blocked
        }
    }

    /// What one external-app hand-off does once its saved choice is known.
    static func externalSchemeConsent(decision: BrowserSitePermissionDecision) -> BrowserExternalSchemeConsent {
        evaluate(.externalConsent, ConsentRequest(decision: decision), answer: ConsentAnswer.self)?.consent ?? .block
    }

    /// An empty component crosses as `null`, as a missing one does.
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
