import CoreGraphics

/// Where a window's sidebar is: beside the page, floating over it, or put away.
struct BrowserSidebarPresentation: Hashable, Sendable {
    // MARK: - Types

    /// Each place shows its own controls, so the places that build them
    /// switch over the kind.
    enum Kinds: Sendable {
        case docked
        case floating
        case collapsed
    }

    // MARK: - Static Variables

    static let docked = BrowserSidebarPresentation(
        kind: .docked, name: "docked", showsSidebar: true, showsWindowControls: true, reservesSidebarWidth: true,
        sidebarToggleAction: .hide)
    static let floating = BrowserSidebarPresentation(
        kind: .floating, name: "floating", showsSidebar: true, showsWindowControls: true, reservesSidebarWidth: false,
        sidebarToggleAction: .dock)
    static let collapsed = BrowserSidebarPresentation(
        kind: .collapsed, name: "collapsed", showsSidebar: false, showsWindowControls: false,
        reservesSidebarWidth: false, sidebarToggleAction: .dock)

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let showsSidebar: Bool
    let showsWindowControls: Bool
    let reservesSidebarWidth: Bool

    /// What the sidebar's toggle does from here.
    let sidebarToggleAction: BrowserSidebarToggleAction

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, showsSidebar: Bool, showsWindowControls: Bool, reservesSidebarWidth: Bool,
        sidebarToggleAction: BrowserSidebarToggleAction
    ) {
        self.kind = kind
        self.name = name
        self.showsSidebar = showsSidebar
        self.showsWindowControls = showsWindowControls
        self.reservesSidebarWidth = reservesSidebarWidth
        self.sidebarToggleAction = sidebarToggleAction
    }

    // MARK: - Actions - Layout

    func reservedWidth(
        for sidebarWidth: CGFloat,
        whileApproachingDock: Bool = false
    ) -> CGFloat {
        reservesSidebarWidth || whileApproachingDock ? sidebarWidth : 0
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarPresentation, rhs: BrowserSidebarPresentation) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
