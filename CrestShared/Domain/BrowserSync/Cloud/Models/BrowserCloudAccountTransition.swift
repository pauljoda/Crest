enum BrowserCloudAccountTransition: Equatable, Sendable {
    case signIn
    case signOut
    case switchAccounts
    case unknown
}
