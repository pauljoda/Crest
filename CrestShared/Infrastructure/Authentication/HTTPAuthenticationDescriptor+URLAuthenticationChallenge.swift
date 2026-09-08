import Foundation

extension BrowserHTTPAuthenticationDescriptor {
    init(challenge: URLAuthenticationChallenge) {
        let protectionSpace = challenge.protectionSpace
        self.init(
            source: Self.sourceLabel(for: protectionSpace),
            realm: protectionSpace.realm,
            authenticationMethod: protectionSpace.authenticationMethod,
            isSecureTransport: protectionSpace.protocol?.lowercased() == "https",
            previousFailureCount: challenge.previousFailureCount
        )
    }

    static func sourceLabel(for protectionSpace: URLProtectionSpace) -> String {
        BrowserHTTPAuthenticationSourcePolicy.label(
            host: protectionSpace.host,
            port: protectionSpace.port,
            scheme: protectionSpace.protocol,
            emptyHostLabel: ProductIdentity.name
        )
    }
}
