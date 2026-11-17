import Foundation

/// What the empty sidebar's context menu offers.
struct BrowserSidebarBackgroundAction: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let editSpace = BrowserSidebarBackgroundAction(
        name: "editSpace", title: "Edit Space…", symbol: "pencil", requiresSpaceCreation: false
    ) { $0.editSpace() }
    static let collapseAllFolders = BrowserSidebarBackgroundAction(
        name: "collapseAllFolders", title: ShortcutCommand.collapseAllFolders.title,
        symbol: ShortcutCommand.collapseAllFolders.symbol, requiresSpaceCreation: false,
        isEnabled: { $0.canCollapseAllFolders() }, animatesSidebar: true, perform: { $0.collapseAllFolders() })
    static let newSpace = BrowserSidebarBackgroundAction(
        name: "newSpace", title: "New Space…", symbol: "plus", requiresSpaceCreation: true
    ) { $0.createSpace?() }
    static let newSubSpace = BrowserSidebarBackgroundAction(
        name: "newSubSpace", title: "New Sub-Space", symbol: "plus.square.on.square", requiresSpaceCreation: true
    ) { $0.createSubSpace?() }

    /// Every action, in menu order.
    static let all: [BrowserSidebarBackgroundAction] = [editSpace, collapseAllFolders, newSpace, newSubSpace]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String

    /// Whether the menu offers the action only where the sidebar can create
    /// Spaces.
    let requiresSpaceCreation: Bool
    /// Whether what it changes in the sidebar moves with the sidebar's
    /// disclosure motion.
    let animatesSidebar: Bool
    private let enablement: @MainActor @Sendable (BrowserSidebarBackgroundInteractionView) -> Bool
    private let performance: @MainActor @Sendable (BrowserSidebarBackgroundInteractionView) -> Void

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String, requiresSpaceCreation: Bool,
        isEnabled: @escaping @MainActor @Sendable (BrowserSidebarBackgroundInteractionView) -> Bool = { _ in true },
        animatesSidebar: Bool = false,
        perform: @escaping @MainActor @Sendable (BrowserSidebarBackgroundInteractionView) -> Void
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.requiresSpaceCreation = requiresSpaceCreation
        self.animatesSidebar = animatesSidebar
        enablement = isEnabled
        performance = perform
    }

    // MARK: - Actions - Performing

    /// Whether the action can run now through the sidebar background `view`,
    /// asked as the menu opens.
    @MainActor
    func isEnabled(on view: BrowserSidebarBackgroundInteractionView) -> Bool {
        enablement(view)
    }

    /// Performs the action through the sidebar background `view` it was
    /// chosen on.
    @MainActor
    func perform(on view: BrowserSidebarBackgroundInteractionView) {
        performance(view)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarBackgroundAction, rhs: BrowserSidebarBackgroundAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
