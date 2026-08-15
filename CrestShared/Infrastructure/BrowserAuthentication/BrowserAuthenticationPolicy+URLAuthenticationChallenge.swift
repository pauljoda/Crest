import Foundation

extension BrowserAuthenticationPolicy {
    static func handling(
        for challenge: URLAuthenticationChallenge
    ) -> BrowserAuthenticationHandling {
        handling(for: BrowserAuthenticationChallenge(challenge))
    }

    static func handling(
        authenticationMethod: String,
        isProxy: Bool,
        previousFailureCount: Int
    ) -> BrowserAuthenticationHandling {
        handling(
            authenticationMethod: BrowserAuthenticationMethod(
                authenticationMethod: authenticationMethod
            ),
            isProxy: isProxy,
            previousFailureCount: previousFailureCount
        )
    }
}
