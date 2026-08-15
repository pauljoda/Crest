import CoreGraphics

/// Geometry and timing owned by the mobile browser composition shell.
enum MobileBrowserRootLayout {
    static let defaultRegularSidebarWidth: CGFloat = 320
    static let resizeHandleOverlap: CGFloat = 8

    static let compactOverlayTopPadding: CGFloat = 12
    static let regularOverlayTopPadding: CGFloat = 18
    static let overlayScrimOpacity = 0.16
    static let overlayShadowOpacity = 0.24
    static let overlayShadowRadius: CGFloat = 18
    static let overlayShadowOffset: CGFloat = 5

    static let feedbackHorizontalPadding: CGFloat = 14
    static let feedbackHeight: CGFloat = 40
    static let feedbackShadowRadius: CGFloat = 16
    static let feedbackShadowOffset: CGFloat = 8
    static let feedbackVisibilityDuration: Duration = .seconds(1.4)

    static let paletteLayer: Double = 10
    static let feedbackLayer: Double = 30
    static let sidebarLayer: Double = 3
    static let utilityLayer: Double = 8
}
