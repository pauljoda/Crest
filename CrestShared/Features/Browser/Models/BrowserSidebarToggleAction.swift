import Foundation

/// What the sidebar's toggle does from where the sidebar is.
struct BrowserSidebarToggleAction: Hashable, Sendable {
    // MARK: - Types

    /// Each action moves the sidebar somewhere else, so the one place that
    /// performs it switches over the kind.
    enum Kinds: Sendable {
        case hide
        case dock
    }

    // MARK: - Static Variables

    static let hide = BrowserSidebarToggleAction(kind: .hide, name: "hide", title: "Hide Sidebar")
    static let dock = BrowserSidebarToggleAction(kind: .dock, name: "dock", title: "Dock Sidebar")

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    // MARK: - Initializers

    private init(kind: Kinds, name: String, title: LocalizedStringResource) {
        self.kind = kind
        self.name = name
        self.title = title
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarToggleAction, rhs: BrowserSidebarToggleAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
