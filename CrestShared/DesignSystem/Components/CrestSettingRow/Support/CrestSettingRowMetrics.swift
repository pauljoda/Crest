import CoreGraphics

/// Measurements shared by every resettable settings row.
enum CrestSettingRowMetrics {
    /// The drawn diameter of a row's reset affordance. It sits in the gap
    /// between a title and its control, so it never takes layout space.
    static let resetDiameter: CGFloat = 18
    /// The gap between the end of a title and its reset affordance.
    static let resetGap: CGFloat = CrestSpacing.small
    static let controlSpacing = CrestSpacing.small
    /// Space between a slider's title/value row and its full-width track.
    static let sliderSpacing = CrestSpacing.small
}
