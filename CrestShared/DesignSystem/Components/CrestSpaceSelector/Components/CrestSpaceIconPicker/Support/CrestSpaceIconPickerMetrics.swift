import CoreGraphics

/// Shared measurements for the compact Space icon picker.
enum CrestSpaceIconPickerMetrics {
    static let segmentWidth: CGFloat = 40
    static let segmentHeight: CGFloat = 30
    static let cornerRadius: CGFloat = CrestRadius.compact
    static let dividerHeight: CGFloat = 18
    static let trackPadding: CGFloat = 3
    static let trackFillOpacity = CrestOpacity.hover
    static let trackBorderOpacity = CrestOpacity.border
    static let selectionFillOpacity = 0.20
    static let overflowButtonWidth: CGFloat = 28
}

/// Styling changes with input size; selection, overflow and actions are shared.
enum CrestSpaceIconPickerStyle {
    case compact
    case touch

    var height: CGFloat {
        self == .touch ? 48 : CrestSpaceIconPickerMetrics.segmentHeight + 2 * CrestSpaceIconPickerMetrics.trackPadding
    }
    var cornerRadius: CGFloat { self == .touch ? height / 2 : CrestSpaceIconPickerMetrics.cornerRadius }
    var minimumSegmentWidth: CGFloat { self == .touch ? 52 : CrestSpaceIconPickerMetrics.segmentWidth }
    var dividerWidth: CGFloat { self == .touch ? 0 : CrestLayout.hairline }
    var overflowButtonWidth: CGFloat { self == .touch ? 44 : CrestSpaceIconPickerMetrics.overflowButtonWidth }
}
