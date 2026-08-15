enum BrowserSidebarToggleAction: Equatable {
    case hide
    case dock

    var title: String {
        switch self {
        case .hide: "Hide Sidebar"
        case .dock: "Show Sidebar"
        }
    }
}
