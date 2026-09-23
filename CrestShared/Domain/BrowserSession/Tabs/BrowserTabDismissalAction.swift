/// Raw values are the core's `tabs.dismissal` spellings.
enum BrowserTabDismissalAction: String, Decodable, Equatable, Sendable {
    case closeTab
    case unloadPage
    case closeWindow
}
