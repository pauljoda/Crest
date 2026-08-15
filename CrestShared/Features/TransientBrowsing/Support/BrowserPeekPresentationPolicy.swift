import SwiftUI

enum BrowserPeekPresentationPolicy {
    static let desktopCardFraction =
        BrowserTransientWindowGeometryPolicy.contentFraction
    static let entranceAnimation = CrestMotion.peekEntrance
    static let initialContentRevealAnimation = CrestMotion.contentReveal

    static func desktopCardSize(in containerSize: CGSize) -> CGSize {
        BrowserTransientWindowGeometryPolicy.contentSize(in: containerSize)
    }

    static func desktopWebContentFrame(
        in containerSize: CGSize,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection
    ) -> CGRect {
        let leadingWidth = min(
            max(reservedLeadingWidth, 0),
            containerSize.width
        )
        return CGRect(
            x: layoutDirection == .leftToRight ? leadingWidth : 0,
            y: 0,
            width: containerSize.width - leadingWidth,
            height: containerSize.height
        )
    }

    static func sourcePresentation(
        touchPoint: CGPoint,
        in webViewSize: CGSize,
        hasTopLeadingOrigin: Bool,
        label: String
    ) -> BrowserPeekSourcePresentation? {
        guard webViewSize.width > 0,
            webViewSize.height > 0,
            touchPoint.x.isFinite,
            touchPoint.y.isFinite
        else { return nil }

        let normalizedX = touchPoint.x / webViewSize.width
        let normalizedY =
            hasTopLeadingOrigin
            ? touchPoint.y / webViewSize.height
            : 1 - touchPoint.y / webViewSize.height
        guard (0...1).contains(normalizedX),
            (0...1).contains(normalizedY)
        else { return nil }

        return BrowserPeekSourcePresentation(
            normalizedMinX: normalizedX,
            normalizedMinY: normalizedY,
            normalizedWidth: 0,
            normalizedHeight: 0,
            normalizedTouchX: normalizedX,
            normalizedTouchY: normalizedY,
            label: label
        )
    }

    static func revealsInitialWebContent(
        committedNavigationCount: Int
    ) -> Bool {
        committedNavigationCount > 0
    }
}
