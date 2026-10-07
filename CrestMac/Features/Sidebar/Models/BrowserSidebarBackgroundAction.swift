import Foundation

/// What the empty sidebar's context menu offers.
struct BrowserSidebarBackgroundAction: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each action does something different, so the one place that performs
    /// an action switches over the kind.
    enum Kinds: Sendable {
        case editSpace
        case newSpace
    }

    // MARK: - Static Variables

    static let editSpace = BrowserSidebarBackgroundAction(
        kind: .editSpace, name: "editSpace", title: "Edit Space…", symbol: "pencil", requiresSpaceCreation: false)
    static let newSpace = BrowserSidebarBackgroundAction(
        kind: .newSpace, name: "newSpace", title: "New Space…", symbol: "plus", requiresSpaceCreation: true)

    /// Every action, in menu order.
    static let all: [BrowserSidebarBackgroundAction] = [editSpace, newSpace]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource
    let symbol: String

    /// Whether the menu offers the action only where the sidebar can create
    /// Spaces.
    let requiresSpaceCreation: Bool

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, symbol: String, requiresSpaceCreation: Bool
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.symbol = symbol
        self.requiresSpaceCreation = requiresSpaceCreation
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarBackgroundAction, rhs: BrowserSidebarBackgroundAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
