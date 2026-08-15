import SwiftUI

struct BrowserManualSetupLayout {
    let isCompact: Bool
    let detailHeight: CGFloat

    init(horizontalSizeClass: UserInterfaceSizeClass?, size: CGSize) {
        isCompact =
            horizontalSizeClass == .compact
            || size.width < BrowserManualSetupLayoutMetrics.compactWidth
        detailHeight = max(
            BrowserManualSetupLayoutMetrics.minimumDetailHeight,
            size.height - BrowserManualSetupLayoutMetrics.detailVerticalMargin
        )
    }
}
