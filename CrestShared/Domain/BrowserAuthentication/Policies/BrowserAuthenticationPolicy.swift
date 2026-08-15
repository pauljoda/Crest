struct BrowserAuthenticationPolicy {
    static let maximumCredentialAttempts = 3

    static func handling(
        authenticationMethod: BrowserAuthenticationMethod,
        isProxy: Bool,
        previousFailureCount: Int
    ) -> BrowserAuthenticationHandling {
        guard !isProxy else { return .performDefaultHandling }

        switch authenticationMethod {
        case .httpBasic, .httpDigest:
            return previousFailureCount < maximumCredentialAttempts
                ? .promptForCredentials
                : .cancel
        case .other:
            return .performDefaultHandling
        }
    }

    static func handling(
        for challenge: BrowserAuthenticationChallenge
    ) -> BrowserAuthenticationHandling {
        handling(
            authenticationMethod: challenge.authenticationMethod,
            isProxy: challenge.isProxy,
            previousFailureCount: challenge.previousFailureCount
        )
    }
}
