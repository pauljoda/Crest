import SwiftUI

enum BrowserChromeDirectionPolicy {
    static func leadingOffset(
        _ distance: CGFloat,
        layoutDirection: LayoutDirection
    ) -> CGFloat {
        layoutDirection == .leftToRight ? distance : -distance
    }

    static func sidebarResizeDelta(
        _ translation: CGFloat,
        layoutDirection: LayoutDirection
    ) -> CGFloat {
        semanticHorizontalTranslation(
            translation,
            layoutDirection: layoutDirection
        )
    }

    static func semanticHorizontalTranslation(
        _ translation: CGFloat,
        layoutDirection: LayoutDirection
    ) -> CGFloat {
        leadingOffset(translation, layoutDirection: layoutDirection)
    }

    static func isLeadingEdgeReveal(
        _ translation: CGSize,
        layoutDirection: LayoutDirection
    ) -> Bool {
        let inwardDistance = semanticHorizontalTranslation(
            translation.width,
            layoutDirection: layoutDirection
        )
        return inwardDistance > 45
            && abs(translation.width) > abs(translation.height)
    }
}
