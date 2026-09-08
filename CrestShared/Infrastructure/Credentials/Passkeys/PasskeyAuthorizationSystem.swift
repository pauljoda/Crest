import AuthenticationServices

@MainActor
enum BrowserPasskeyAuthorizationSystem {
    static func deviceConfiguration() -> BrowserPasskeyDeviceConfiguration {
        if #available(macOS 26.2, iOS 26.2, *) {
            return ASAuthorizationWebBrowserPublicKeyCredentialManager
                .isDeviceConfiguredForPasskeys ? .configured : .notConfigured
        }
        return .unknown
    }

    static func authorizationState() -> BrowserPasskeyAuthorizationState {
        BrowserPasskeyAuthorizationState(
            ASAuthorizationWebBrowserPublicKeyCredentialManager()
                .authorizationStateForPlatformCredentials
        )
    }

    static func requestAuthorization() async -> BrowserPasskeyAuthorizationState {
        let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        return await withCheckedContinuation { continuation in
            manager.requestAuthorizationForPublicKeyCredentials { state in
                continuation.resume(
                    returning: BrowserPasskeyAuthorizationState(state)
                )
            }
        }
    }
}
