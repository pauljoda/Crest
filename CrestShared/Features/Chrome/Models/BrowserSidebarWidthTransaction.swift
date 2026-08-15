import CoreGraphics

/// Keeps pointer-frequency resize updates in view-owned memory. Durable
/// preferences advance only when the interaction commits, which avoids making
/// UserDefaults an animation-rate source of SwiftUI invalidations.
struct BrowserSidebarWidthTransaction: Equatable {
    private(set) var width: CGFloat
    private(set) var persistedWidth: CGFloat

    init(persistedWidth: CGFloat) {
        let width = BrowserChromeLayout.clampedSidebarWidth(persistedWidth)
        self.width = width
        self.persistedWidth = width
    }

    mutating func resize(to proposedWidth: CGFloat) {
        width = BrowserChromeLayout.clampedSidebarWidth(proposedWidth)
    }

    mutating func commit() -> CGFloat? {
        guard width != persistedWidth else { return nil }
        persistedWidth = width
        return width
    }

    mutating func restore(persistedWidth: CGFloat) {
        let width = BrowserChromeLayout.clampedSidebarWidth(persistedWidth)
        self.width = width
        self.persistedWidth = width
    }
}
