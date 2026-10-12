import CoreGraphics

/// How a regular window fits its sidebar: beside the page when the page
/// keeps a usable width, and otherwise over it.
struct MobileRegularWindowLayout: Equatable, Sendable {
    // MARK: - Static Variables

    /// Leaves enough room for an actually usable web viewport while retaining
    /// the iPad sidebar anatomy for every ordinary Stage Manager width.
    static let minimumDetailWidth: CGFloat = 320
    static let overlayEdgeClearance: CGFloat = 44

    // MARK: - Variables

    let sidebarWidth: CGFloat

    /// Whether the sidebar sits beside the page, taking its width from it,
    /// rather than over it.
    let reservesSidebarWidth: Bool

    // MARK: - Initializers

    init(availableWidth: CGFloat, preferredSidebarWidth: CGFloat) {
        let availableWidth = max(0, availableWidth)
        let preferredSidebarWidth = BrowserChromeLayout.clampedSidebarWidth(
            preferredSidebarWidth
        )
        let sideBySideLimit = availableWidth - Self.minimumDetailWidth

        if sideBySideLimit >= BrowserChromeLayout.sidebarMinimumWidth {
            sidebarWidth = min(preferredSidebarWidth, sideBySideLimit)
            reservesSidebarWidth = true
            return
        }

        sidebarWidth = min(
            preferredSidebarWidth,
            max(0, availableWidth - Self.overlayEdgeClearance)
        )
        reservesSidebarWidth = false
    }
}
