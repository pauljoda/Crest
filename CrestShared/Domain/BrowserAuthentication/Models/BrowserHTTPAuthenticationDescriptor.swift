struct BrowserHTTPAuthenticationDescriptor: Equatable, Sendable {
    let source: String
    let realm: String?
    let authenticationMethod: String
    let isSecureTransport: Bool
    let previousFailureCount: Int
}
