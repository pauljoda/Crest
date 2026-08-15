struct BrowserAuthenticationChallenge: Equatable, Sendable {
    let authenticationMethod: BrowserAuthenticationMethod
    let isProxy: Bool
    let previousFailureCount: Int
    let protectionSpace: BrowserHTTPAuthenticationProtectionSpace?
    let descriptor: BrowserHTTPAuthenticationDescriptor
    let proposedUsername: String?
}
