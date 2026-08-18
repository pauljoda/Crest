enum BrowserSidebarToggleAction: Equatable, Sendable {
    case hide
    case dock

    var title: String {
        switch self {
        case .hide: "Hide Sidebar"
        case .dock: "Dock Sidebar"
        }
    }
}
