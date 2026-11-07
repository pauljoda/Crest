import CoreGraphics

/// Keeps resize updates local until the interaction commits.
struct BrowserSidebarWidthTransaction: Equatable {
    // MARK: - Variables

    private(set) var width: CGFloat
    private(set) var persistedWidth: CGFloat

    /// Whether a resize is under way: from its first update until it commits,
    /// even while the width it proposes is the one it started from.
    private(set) var isResizing = false

    // MARK: - Initializers

    init(persistedWidth: CGFloat) {
        let width = BrowserChromeLayout.clampedSidebarWidth(persistedWidth)
        self.width = width
        self.persistedWidth = width
    }

    // MARK: - Mutators

    mutating func resize(to proposedWidth: CGFloat) {
        width = BrowserChromeLayout.clampedSidebarWidth(proposedWidth)
        isResizing = true
    }

    mutating func commit() -> CGFloat? {
        isResizing = false
        guard width != persistedWidth else { return nil }
        persistedWidth = width
        return width
    }

    mutating func restore(persistedWidth: CGFloat) {
        let width = BrowserChromeLayout.clampedSidebarWidth(persistedWidth)
        self.width = width
        self.persistedWidth = width
        isResizing = false
    }
}
