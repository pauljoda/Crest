import SwiftUI

enum BrowserSidebarPresentationPolicy {
    static let floatingCardInset: CGFloat = 7

    static func floatingHoverRegionWidth(sidebarWidth: CGFloat) -> CGFloat {
        sidebarWidth + (floatingCardInset * 2)
    }
    static let floatingCardCornerRadius: CGFloat = 18

    static func presentation(
        columnVisibility: NavigationSplitViewVisibility,
        isFloatingSidebarPresented: Bool
    ) -> BrowserSidebarPresentation {
        guard columnVisibility == .detailOnly else { return .docked }
        return isFloatingSidebarPresented ? .floating : .collapsed
    }
}
