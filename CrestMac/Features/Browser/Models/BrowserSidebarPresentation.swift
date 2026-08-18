import CoreGraphics

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

    func reservedWidth(
        for sidebarWidth: CGFloat,
        whileApproachingDock: Bool = false
    ) -> CGFloat {
        reservesSidebarWidth || whileApproachingDock ? sidebarWidth : 0
    }

    var sidebarToggleAction: BrowserSidebarToggleAction {
        self == .docked ? .hide : .dock
    }

}
