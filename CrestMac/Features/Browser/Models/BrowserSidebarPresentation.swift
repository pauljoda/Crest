enum BrowserSidebarPresentation: Equatable {
    case docked
    case floating
    case collapsed

    var showsSidebar: Bool {
        self != .collapsed
    }

    var showsWindowControls: Bool {
        self != .collapsed
    }

    var reservesSidebarWidth: Bool {
        self == .docked
    }

    var sidebarToggleAction: BrowserSidebarToggleAction {
        self == .docked ? .hide : .dock
    }
}
