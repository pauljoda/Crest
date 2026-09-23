import Foundation

/// How the engine judged the connection behind a page's current document. Each
/// engine adapter derives it from its own security model; the raw values are
/// the Chromium host's `changed` spelling.
enum BrowserPageSecurityState: String, Codable, Sendable, CaseIterable {
    /// Nothing to judge: no document yet, a local or internal page, or a load
    /// that failed before a connection was made.
    case none
    /// A document delivered without transport security, such as plain HTTP.
    case insecure
    /// A verified TLS connection with no insecure content.
    case secure
    /// A verified TLS connection whose document also shows or runs content
    /// that was not delivered securely.
    case mixedContent = "mixed_content"
    /// The site's certificate is not trusted: the engine's warning page, or a
    /// page reached past it.
    case certificateError = "certificate_error"
    /// The engine flagged the page itself as malicious or deceptive.
    case dangerous

    // MARK: - Variables

    var isSecure: Bool { self == .secure }
}
