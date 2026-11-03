import Foundation
import Security

extension PageSecurityFacts {
    /// What WebKit knows of a page's connection, which the core judges.
    /// WebKit reports only whether every resource arrived securely, and blocks
    /// the active content it would run, so mixed content is what it displayed.
    /// A certificate error is recognized from the trust it kept: an evaluation
    /// that failed, or a certificate the person chose to trust for this
    /// profile, which Crest records only for a failing one. WebKit judges a
    /// document's connection as it shows it, flags no page as malicious,
    /// shows no error page of its own and words no warning about a
    /// connection.
    init(
        webKitURL url: URL?,
        hasOnlySecureContent: Bool,
        serverTrust: SecTrust?,
        isApprovedOverride: (BrowserServerTrustIdentity) -> Bool
    ) {
        let cryptographic = WebScheme.named(url?.scheme?.lowercased())?.isSecure == true
        var certificateError = false
        if cryptographic, let url, let serverTrust {
            certificateError = Self.isCertificateError(serverTrust, url: url, isApprovedOverride: isApprovedOverride)
        }
        self.init(
            cryptographicScheme: cryptographic,
            connectionJudged: url != nil,
            certificateError: certificateError,
            engineWarns: false,
            mixedContent: cryptographic && !hasOnlySecureContent ? .displayed : [],
            maliciousContent: false,
            errorPage: false)
    }

    // MARK: - Actions - Trust

    private static func isCertificateError(
        _ trust: SecTrust,
        url: URL,
        isApprovedOverride: (BrowserServerTrustIdentity) -> Bool
    ) -> Bool {
        // The result WebKit's own evaluation left on the trust, read without
        // evaluating it again on the main thread.
        var result = SecTrustResultType.invalid
        if SecTrustGetTrustResult(trust, &result) == errSecSuccess {
            switch result {
            case .deny, .recoverableTrustFailure, .fatalTrustFailure, .otherError: return true
            default: break
            }
        }
        guard let host = url.host(),
            let identity = BrowserServerTrustIdentity.identity(for: trust, host: host, port: url.port ?? 443)
        else { return false }
        return isApprovedOverride(identity)
    }
}
