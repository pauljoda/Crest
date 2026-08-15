import SwiftUI

enum MobileBrowserTransientLayout {
    static let controlHeight = BrowserPeekChromePolicy.controlHeight
    static let overlayLayer: Double = 20

    static func sourceCardTransform(
        for source: BrowserPeekSourcePresentation
    ) -> MobileBrowserPeekSourceTransform {
        MobileBrowserPeekSourceTransform(
            anchor: UnitPoint(
                x: source.normalizedTouchX,
                y: source.normalizedTouchY
            ),
            scaleX: min(max(source.normalizedWidth, 0.06), 0.42),
            scaleY: min(max(source.normalizedHeight, 0.035), 0.24)
        )
    }

    static func cardInsets(
        safeAreaInsets: EdgeInsets,
        minimumHorizontal: CGFloat,
        minimumVertical: CGFloat
    ) -> EdgeInsets {
        EdgeInsets(
            top: max(safeAreaInsets.top, minimumVertical),
            leading: max(safeAreaInsets.leading, minimumHorizontal),
            bottom: max(safeAreaInsets.bottom, minimumVertical),
            trailing: max(safeAreaInsets.trailing, minimumHorizontal)
        )
    }
}
