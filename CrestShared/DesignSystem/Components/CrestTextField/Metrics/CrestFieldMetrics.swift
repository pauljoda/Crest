import CoreGraphics

/// The single field treatment: one radius, one hairline, and one focus ring.
enum CrestFieldMetrics {
    static let cornerRadius: CGFloat = CrestRadius.control
    static let height: CGFloat = 40
    static let horizontalPadding: CGFloat = CrestSpacing.medium
    static let borderWidth: CGFloat = CrestLayout.hairline
    static let focusRingWidth: CGFloat = CrestLayout.focusRing
    static let focusRingOpacity = 0.32

    /// A search field's height where only a pointer aims at it, and where a
    /// finger may.
    static let pointerSearchHeight: CGFloat = 30
    static let touchSearchHeight: CGFloat = 44
    /// The circle of the control that clears a search, and how far past it a
    /// finger's presses reach, filling a touch field's height.
    static let clearControlDiameter: CGFloat = 22
    static let clearControlTouchOutset: CGFloat = (touchSearchHeight - clearControlDiameter) / 2
}
