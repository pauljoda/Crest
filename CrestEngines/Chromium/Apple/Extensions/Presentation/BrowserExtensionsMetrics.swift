import CoreGraphics

enum BrowserExtensionsMetrics {
    static let scopeIconSize: CGFloat = 30
    static let scopeActionSize: CGFloat = 32
    static let extensionIconSize: CGFloat = 28
    static let discoveryIconSize: CGFloat = 44
    static let installReviewIconSize: CGFloat = 52
    static let expandedContentIndent: CGFloat = 40
    static let extensionIconCornerRadiusRatio: CGFloat = 0.2
    static let extensionIconFallbackPaddingRatio: CGFloat = 0.18
    static let extensionIconDecodedPixelScale: CGFloat = 3
    static let minimumExtensionIconDecodedPixelSize = 64
    static let renderedExtensionIconScale: CGFloat = 1
    static let updateStatusSpacing: CGFloat = 8

    static func maximumDecodedPixelSize(for size: CGFloat) -> Int {
        max(
            minimumExtensionIconDecodedPixelSize,
            Int((size * extensionIconDecodedPixelScale).rounded(.up))
        )
    }
}
