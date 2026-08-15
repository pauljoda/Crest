enum BrowserDefaultBrowserStatus: Equatable, Sendable {
    case unknown
    case isDefault
    case notDefault
    case unavailable(String)
}
