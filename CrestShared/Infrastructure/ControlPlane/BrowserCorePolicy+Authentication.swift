import Foundation

/// HTTP authentication rules answered by the portable core. No username or
/// password crosses: a challenge is its method, proxy flag and failure count.
extension BrowserCorePolicy {
    /// How one challenge is answered. An unavailable core cancels the
    /// challenge rather than prompting or handing over stored credentials.
    static func authenticationHandling(for challenge: BrowserAuthenticationChallenge) -> BrowserAuthenticationHandling {
        authenticationHandling(method: challenge.authenticationMethod, isProxy: challenge.isProxy,
            previousFailureCount: challenge.previousFailureCount)
    }

    static func authenticationHandling(method: BrowserAuthenticationMethod, isProxy: Bool,
        previousFailureCount: Int) -> BrowserAuthenticationHandling {
        let code = switch method {
        case .httpBasic: "httpBasic"
        case .httpDigest: "httpDigest"
        case .other: "other"
        }
        switch evaluate(["version": 1, "operation": "authentication.handling", "method": code,
            "isProxy": isProxy, "previousFailureCount": previousFailureCount])?["handling"] as? String {
        case "promptForCredentials": return .promptForCredentials
        case "performDefaultHandling": return .performDefaultHandling
        default: return .cancel
        }
    }

    /// The server as the credential prompt names it. The core owns the
    /// formatting; without its answer the prompt uses the generic label. A
    /// prompt never appears without the core in practice, because
    /// `authenticationHandling` cancels the challenge when it cannot answer.
    static func authenticationSourceLabel(host: String, port: Int, scheme: String?, emptyHostLabel: String) -> String {
        let scheme = scheme.flatMap { $0.isEmpty ? nil : $0 }
        return evaluate(["version": 1, "operation": "authentication.source_label", "host": host,
            "port": port, "scheme": scheme as Any? ?? NSNull()])?["label"] as? String ?? emptyHostLabel
    }

    /// Whether the physical-validation fixture build trusts this server
    /// certificate. An unavailable core trusts nothing.
    static func trustsPhysicalValidationServer(bundleIdentifier: String?, expectedCertificateSHA256: String?,
        actualCertificateSHA256: String) -> Bool {
        evaluate(["version": 1, "operation": "authentication.fixture_trust",
            "bundleIdentifier": bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 } as Any? ?? NSNull(),
            "expectedCertificateSHA256": expectedCertificateSHA256.flatMap { $0.isEmpty ? nil : $0 } as Any? ?? NSNull(),
            "actualCertificateSHA256": actualCertificateSHA256])?["allowed"] as? Bool ?? false
    }
}
