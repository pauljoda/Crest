import CoreGraphics

enum BrowserPinnedExtensionStripLayoutPolicy {
    static let tileSize: CGFloat = 24
    static let sectionHeight: CGFloat = 32
    static let sectionCornerRadius = BrowserChromeLayout.addressCornerRadius
    static let glyphSize: CGFloat = 16
    static let spacing: CGFloat = 6
    static let pinControlSize: CGFloat = 14
    static let adjacentSpacing = CrestSpacing.small
    static let popupGap: CGFloat = 6

    static func height(for actionCount: Int) -> CGFloat {
        actionCount > 0 ? sectionHeight : 0
    }

    static func pinnedTabsTopInset(
        hasPinnedExtensions: Bool
    ) -> CGFloat {
        hasPinnedExtensions ? 0 : CrestSpacing.small
    }

    static func addressBottomInset(
        hasPinnedExtensions: Bool
    ) -> CGFloat {
        hasPinnedExtensions
            ? adjacentSpacing
            : BrowserSidebarMetrics.addressBottomInset
    }

    static func popupAnchor(below interactionPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: interactionPoint.x,
            y: interactionPoint.y - tileSize / 2 - popupGap
        )
    }
}
