import CoreGraphics

enum MobileRegularWindowLayoutPolicy {
    /// Leaves enough room for an actually usable web viewport while retaining
    /// the iPad sidebar anatomy for every ordinary Stage Manager width.
    static let minimumDetailWidth: CGFloat = 320
    static let overlayEdgeClearance: CGFloat = 44

    static func resolve(
        availableWidth: CGFloat,
        preferredSidebarWidth: CGFloat
    ) -> MobileRegularWindowLayout {
        let availableWidth = max(0, availableWidth)
        let preferredSidebarWidth = BrowserChromeLayout.clampedSidebarWidth(
            preferredSidebarWidth
        )
        let sideBySideLimit = availableWidth - minimumDetailWidth

        if sideBySideLimit >= BrowserChromeLayout.sidebarMinimumWidth {
            return .sideBySide(
                sidebarWidth: min(preferredSidebarWidth, sideBySideLimit)
            )
        }

        return .overlay(
            sidebarWidth: min(
                preferredSidebarWidth,
                max(0, availableWidth - overlayEdgeClearance)
            )
        )
    }
}
