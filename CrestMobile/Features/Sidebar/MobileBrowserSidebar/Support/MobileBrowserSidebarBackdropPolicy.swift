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

    /// Whether one Space's page draws its branded ground.
    ///
    /// The shell says whether it paints its own ground at all; paging state and
    /// selection stay in the signature because a single full-bleed layer is a
    /// choice this policy makes rather than one its callers should assume.
    static func showsPageBackdrop(
        showsPageBackdrop: Bool,
        isPaging _: Bool,
        isSelected _: Bool
    ) -> Bool {
        showsPageBackdrop
    }

    static func branding(for space: BrowserSpace) -> BrowserSpaceBranding {
        space.branding
    }
}
