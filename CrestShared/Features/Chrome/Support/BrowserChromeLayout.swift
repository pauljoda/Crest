import SwiftUI

enum BrowserChromeLayout {
    static let sidebarTitlebarHeight: CGFloat = 48
    static let sidebarNavigationControlHitTarget: CGFloat = 30
    static let sidebarNavigationSymbolPointSize: CGFloat = 15
    static let sidebarNavigationTrailingInset = CrestSpacing.medium
    static let addressEditingRingWidth: CGFloat = 0.5
    static let addressHeight: CGFloat = 36
    static let addressCornerRadius = CrestRadius.compact
    /// About as narrow as Arc's sidebar goes. Below the navigation strip's
    /// fold width, Forward folds away to keep clear of the window's own
    /// controls.
    static let sidebarMinimumWidth: CGFloat = 164
    static let sidebarIdealWidth: CGFloat = 289
    static let sidebarMaximumWidth: CGFloat = 380
    static let pageFrameInset = CrestSpacing.small
    /// A page's corner where there is no window corner to follow: full screen,
    /// iPhone and iPad.
    static let pageCornerRadius: CGFloat = 13
    static let pageBrandSeamWidth: CGFloat = 1.5

    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sidebarMinimumWidth), sidebarMaximumWidth)
    }
}
