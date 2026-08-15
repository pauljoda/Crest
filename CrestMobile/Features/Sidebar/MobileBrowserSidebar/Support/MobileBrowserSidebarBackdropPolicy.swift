import SwiftUI

enum MobileBrowserSidebarBackdropPolicy {
    static let usesMatchedGeometryMorph = false
    static let usesOpacityCrossfade = false
    static let pagerOwnsFullSurface = true
    static let pageBackdropIgnoresSafeArea = true
    static let usesSingleBackdropLayer = true
    static let requiresPagingStateUpdates = false

    static func style(isPaging _: Bool) -> MobileBrowserSidebarBackdropStyle {
        MobileBrowserSidebarBackdropStyle(
            usesSharedSelectedSpaceBackdrop: false,
            horizontalInset: 0,
            verticalInset: 0,
            cornerRadius: 0,
            outlineOpacity: 0
        )
    }

    static func isFullBleed(isPaging _: Bool) -> Bool {
        true
    }

    static func showsPageBackdrop(
        for mode: MobileBrowserSidebarMode,
        isPaging _: Bool,
        isSelected _: Bool
    ) -> Bool {
        mode == .compactTabViewer
    }

    static func branding(for space: BrowserSpace) -> BrowserSpaceBranding {
        space.branding
    }
}
