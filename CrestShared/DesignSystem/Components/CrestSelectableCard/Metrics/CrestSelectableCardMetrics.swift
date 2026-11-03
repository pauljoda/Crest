import CoreGraphics

/// Selection-card measurements shared by every density.
enum CrestSelectableCardMetrics {
    static let selectedBorderWidth: CGFloat = CrestLayout.pinnedAccentBorderWidth
    static let contentSpacing: CGFloat = CrestSpacing.medium
    static let selectedFillOpacity = CrestButtonMetrics.tintRestFill
    static let checkmarkSize: CGFloat = 20
    static let checkmarkSymbol = "checkmark.circle.fill"
}
