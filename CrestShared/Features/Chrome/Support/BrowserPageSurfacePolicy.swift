import CoreGraphics

enum BrowserPageSurfacePolicy {
    static let usesRootElevation = true
    static let usesExplicitExteriorShadowPath = true
    static let usesSharedRootContentSurface = true
    static let rootSurfaceOwnsClippingAndSeam = true
    static let collapsedSidebarKeepsFreestandingFrame = true
    static let quickWindowReusesRootContentSurface = true
    static let rootOwnsSpaceAtmosphere = true
    static let pageSurfacePaintsSpaceAtmosphere = false
    static let embedsStartPageRecess = false
    static let showsUnloadedPlaceholder = false
    static let startPageUsesSpaceAtmosphere = true
    static let usesSingleContinuousRootMask = true
    static let startPageUsesTransparentInnerSurface = true
    static let usesNativeSwiftUIShadow = true
    static let shadowOpacity = 0.11
    static let shadowRadius: CGFloat = 7
    static let shadowYOffset: CGFloat = 2
    static let usesCrispBoundaryStroke = true
    static let shadowUsesContinuousSurfacePath = true
    static let shadowExcludesSurfaceInterior = true
    static let shadowAllocatesExteriorDrawingOutset = true
    static let shadowDrawingOutset = shadowRadius * 2 + abs(shadowYOffset)
    static let boundaryStrokeUsesSemanticForeground = false
    static let boundaryStrokeUsesDarkNeutral = true
    static let boundaryStrokeWidth: CGFloat = 0.5
    static let boundaryStrokeOpacity = CrestOpacity.border

    static func usesTransparentInnerSurface(
        isStartPage: Bool,
        hasActivePage: Bool,
        completedNavigationCount: Int
    ) -> Bool {
        (startPageUsesSpaceAtmosphere
            && startPageUsesTransparentInnerSurface
            && isStartPage)
            || !hasActivePage
            || completedNavigationCount == 0
    }

    static func revealsWebContent(completedNavigationCount: Int) -> Bool {
        completedNavigationCount > 0
    }

    static func revealsWebContent(committedNavigationCount: Int) -> Bool {
        committedNavigationCount > 0
    }
}
