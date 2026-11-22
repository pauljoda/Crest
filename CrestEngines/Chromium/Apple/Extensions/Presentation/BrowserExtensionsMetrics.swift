import CoreGraphics

enum BrowserExtensionsMetrics {
    static let extensionIconSize: CGFloat = 28
    static let installReviewIconSize: CGFloat = 52
    static let expandedContentIndent: CGFloat = 40
    static let extensionIconCornerRadiusRatio: CGFloat = 0.2
    static let extensionIconFallbackPaddingRatio: CGFloat = 0.18
    static let extensionIconDecodedPixelScale: CGFloat = 3
    static let minimumExtensionIconDecodedPixelSize = 64
    /// An action's badge: its side when it holds one character, the room
    /// either side of longer text, and how far it sits up and out from the
    /// icon's corner.
    static let badgeMinimumSize: CGFloat = 12
    static let badgeHorizontalPadding: CGFloat = 3
    static let badgeOffset: CGFloat = 5

    static func maximumDecodedPixelSize(for size: CGFloat) -> Int {
        max(
            minimumExtensionIconDecodedPixelSize,
            Int((size * extensionIconDecodedPixelScale).rounded(.up))
        )
    }
}
