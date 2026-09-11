import CoreGraphics

/// Measurements shared by every resettable settings row.
enum CrestSettingRowMetrics {
    /// The drawn diameter of a row's reset affordance. It sits in the gap
    /// between a title and its control, so it never takes layout space.
    static let resetDiameter: CGFloat = 18
    /// The gap between the end of a title and its reset affordance.
    static let resetGap: CGFloat = CrestSpacing.small
    static let controlSpacing = CrestSpacing.small
    /// A slider's track is a fixed width so every slider row lines up and the
    /// readout beside it stays in one column.
    static let sliderWidth: CGFloat = 156
    /// Fixed rather than minimum, so "Borderless" and "7 pt" hold the track in
    /// the same place.
    static let readoutWidth: CGFloat = 68
}
