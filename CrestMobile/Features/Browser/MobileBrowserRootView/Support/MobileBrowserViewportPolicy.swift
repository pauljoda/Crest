import SwiftUI
import UIKit

enum MobileBrowserViewportPolicy {
    /// The 44-point controls plus six points above and below their glass scope.
    static let compactToolbarHeight: CGFloat = 56
    static let compactDomainChipHeight = MobileCompactDomainChipLayout.minimumHitTarget

    /// SwiftUI's directional safe area as the physical one UIKit lays out with.
    static func systemSafeAreaInsets(
        _ insets: EdgeInsets,
        layoutDirection: LayoutDirection
    ) -> UIEdgeInsets {
        let isRightToLeft = layoutDirection == .rightToLeft
        return UIEdgeInsets(
            top: insets.top,
            left: isRightToLeft ? insets.trailing : insets.leading,
            bottom: insets.bottom,
            right: isRightToLeft ? insets.leading : insets.trailing
        )
    }

    static func webViewFrameInsets(
        safeAreaInsets: UIEdgeInsets,
        bottomChromeHeight _: CGFloat
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: safeAreaInsets.top,
            left: safeAreaInsets.left,
            bottom: 0,
            right: safeAreaInsets.right
        )
    }

    static func chromeOverlayInsets(
        safeAreaInsets: UIEdgeInsets,
        bottomChromeHeight: CGFloat
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: safeAreaInsets.bottom + max(0, bottomChromeHeight),
            right: 0
        )
    }

    static func viewportRangeInsets(
        safeAreaInsets: UIEdgeInsets
    ) -> (minimum: UIEdgeInsets, maximum: UIEdgeInsets) {
        (
            minimum: chromeOverlayInsets(
                safeAreaInsets: safeAreaInsets,
                bottomChromeHeight: compactDomainChipHeight
            ),
            maximum: chromeOverlayInsets(
                safeAreaInsets: safeAreaInsets,
                bottomChromeHeight: compactToolbarHeight
            )
        )
    }
}

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
