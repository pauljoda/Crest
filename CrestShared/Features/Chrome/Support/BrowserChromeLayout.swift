import SwiftUI

enum BrowserChromeLayout {
    static let addressPlacement = BrowserAddressPlacement.spaceSidebar
    static let navigationPlacement = BrowserAddressPlacement.spaceSidebar
    static let hidesWindowToolbar = false
    static let showsWindowToolbarBackground = false
    static let pageExtendsUnderTitlebar = true
    static let windowControlsMoveWithSidebar = true
    static let usesSystemWindowControls = true
    static let preservesSystemWindowControlFrames = true
    static let usesSystemToolbarTitlebarMetrics = true
    static let usesSystemWindowControlColors = true
    static let usesSystemWindowControlActions = true
    static let sidebarTitlebarHeight: CGFloat = 48
    static let windowControlsReservedWidth: CGFloat = 67
    static let sidebarToggleLeadingInset = CrestSpacing.medium
    static let sidebarToggleSymbolOffsetY: CGFloat = 1
    static let sidebarNavigationControlHitTarget: CGFloat = 30
    static let sidebarNavigationSymbolPointSize: CGFloat = 15
    static let sidebarNavigationTrailingInset = CrestSpacing.medium
    static let sidebarNavigationControlOrder: [BrowserSidebarNavigationControl] = [
        .back,
        .forward,
    ]
    static let addressUsesCustomGlass = false
    static let addressSurfaceOpacity = CrestOpacity.chromeSurface
    static let addressEditingRingUsesAccent = false
    static let addressEditingRingWidth: CGFloat = 0.5
    static let addressHeight: CGFloat = 36
    static let addressCornerRadius = CrestRadius.compact
    static let sidebarHorizontalInset = CrestSpacing.small
    static let sidebarMinimumWidth: CGFloat = 260
    static let sidebarIdealWidth: CGFloat = 289
    static let sidebarMaximumWidth: CGFloat = 380
    static let pageFrameInset = CrestSpacing.small
    static let pageCornerRadius: CGFloat = 13
    static let pageBrandSeamWidth: CGFloat = 1.5

    static var pageContentCornerRadius: CGFloat {
        pageCornerRadius - pageBrandSeamWidth
    }

    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sidebarMinimumWidth), sidebarMaximumWidth)
    }

    static func pageFrameInsets(
        adjoinsLeadingSidebar: Bool
    ) -> EdgeInsets {
        EdgeInsets(
            top: pageFrameInset,
            leading: adjoinsLeadingSidebar ? 0 : pageFrameInset,
            bottom: pageFrameInset,
            trailing: pageFrameInset
        )
    }
}
