enum BrowserHTTPAuthenticationDecision: Sendable {
    case performDefaultHandling
    case cancel
    case useCredential(username: String, password: String)
}
