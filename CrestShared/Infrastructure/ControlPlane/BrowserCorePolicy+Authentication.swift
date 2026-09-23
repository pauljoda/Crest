import Foundation

/// HTTP authentication rules answered by the portable core. No username or
/// password crosses: a challenge is its method, proxy flag and failure count.
extension BrowserCorePolicy {
    // MARK: - Types

    private struct HandlingRequest: Encodable {
        let method: BrowserAuthenticationMethod
        let isProxy: Bool
        let previousFailureCount: Int
    }

    private struct HandlingAnswer: Decodable {
        @BrowserCoreOptional var handling: BrowserAuthenticationHandling?
    }

    private struct SourceLabelRequest: Encodable {
        let host: String
        let port: Int
        @BrowserCoreNullable var scheme: String?
    }

    private struct SourceLabelAnswer: Decodable {
        @BrowserCoreOptional var label: String?
    }

    private struct FixtureTrustRequest: Encodable {
        @BrowserCoreNullable var bundleIdentifier: String?
        @BrowserCoreNullable var expectedCertificateSHA256: String?
        let actualCertificateSHA256: String
    }

    private struct AllowedAnswer: Decodable {
        @BrowserCoreOptional var allowed: Bool?
    }

    // MARK: - Actions - Authentication

    /// How one challenge is answered. An unavailable core cancels the
    /// challenge rather than prompting or handing over stored credentials.
    static func authenticationHandling(for challenge: BrowserAuthenticationChallenge) -> BrowserAuthenticationHandling {
        authenticationHandling(
            method: challenge.authenticationMethod, isProxy: challenge.isProxy,
            previousFailureCount: challenge.previousFailureCount)
    }

    static func authenticationHandling(
        method: BrowserAuthenticationMethod, isProxy: Bool,
        previousFailureCount: Int
    ) -> BrowserAuthenticationHandling {
        let request = HandlingRequest(method: method, isProxy: isProxy, previousFailureCount: previousFailureCount)
        return evaluate(.authenticationHandling, request, answer: HandlingAnswer.self)?.handling ?? .cancel
    }

    /// The server as the credential prompt names it. The core owns the
    /// formatting; without its answer the prompt uses the generic label. A
    /// prompt never appears without the core in practice, because
    /// `authenticationHandling` cancels the challenge when it cannot answer.
    static func authenticationSourceLabel(host: String, port: Int, scheme: String?, emptyHostLabel: String) -> String {
        let request = SourceLabelRequest(host: host, port: port, scheme: scheme.flatMap { $0.isEmpty ? nil : $0 })
        return evaluate(.authenticationSourceLabel, request, answer: SourceLabelAnswer.self)?.label ?? emptyHostLabel
    }

    /// Whether the physical-validation fixture build trusts this server
    /// certificate. An unavailable core trusts nothing.
    static func trustsPhysicalValidationServer(
        bundleIdentifier: String?, expectedCertificateSHA256: String?,
        actualCertificateSHA256: String
    ) -> Bool {
        let request = FixtureTrustRequest(
            bundleIdentifier: bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 },
            expectedCertificateSHA256: expectedCertificateSHA256.flatMap { $0.isEmpty ? nil : $0 },
            actualCertificateSHA256: actualCertificateSHA256)
        return evaluate(.authenticationFixtureTrust, request, answer: AllowedAnswer.self)?.allowed ?? false
    }
}
