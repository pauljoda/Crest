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
struct CrestSpaceIconPickerStyle: Hashable, Sendable {
    // MARK: - Static Variables

    static let compact = CrestSpaceIconPickerStyle(
        name: "compact",
        height: CrestSpaceIconPickerMetrics.segmentHeight + 2 * CrestSpaceIconPickerMetrics.trackPadding,
        fixedCornerRadius: CrestSpaceIconPickerMetrics.cornerRadius,
        minimumSegmentWidth: CrestSpaceIconPickerMetrics.segmentWidth, dividerWidth: CrestLayout.hairline,
        overflowButtonWidth: CrestSpaceIconPickerMetrics.overflowButtonWidth, showsDividers: true,
        fillsSegments: false, trackFillOpacity: CrestSpaceIconPickerMetrics.trackFillOpacity,
        trackBorderOpacity: CrestSpaceIconPickerMetrics.trackBorderOpacity, tintsSelection: true,
        selectionFillOpacity: CrestSpaceIconPickerMetrics.selectionFillOpacity, shrinksWithCrest: true)
    static let touch = CrestSpaceIconPickerStyle(
        name: "touch", height: 48, fixedCornerRadius: nil, minimumSegmentWidth: 52, dividerWidth: 0,
        overflowButtonWidth: 44, showsDividers: false, fillsSegments: true, trackFillOpacity: 0.08,
        trackBorderOpacity: 0, tintsSelection: false, selectionFillOpacity: 0.22, shrinksWithCrest: false)

    // MARK: - Variables

    let name: String
    let height: CGFloat

    /// The corner radius every part of the picker shares, or `nil` where each
    /// part is a capsule.
    let fixedCornerRadius: CGFloat?

    let minimumSegmentWidth: CGFloat
    let dividerWidth: CGFloat
    let overflowButtonWidth: CGFloat

    /// Whether a divider stands between neighbouring Spaces.
    let showsDividers: Bool

    /// Whether the segments widen to share the whole width the picker has.
    let fillsSegments: Bool

    let trackFillOpacity: Double
    let trackBorderOpacity: Double

    /// Whether the selected Space wears its own tint and outline, or a
    /// neutral fill.
    let tintsSelection: Bool

    let selectionFillOpacity: Double

    /// Whether segments shrink with a smaller crest. Touch keeps its segments
    /// at full size so each Space stays a target a finger can hit.
    let shrinksWithCrest: Bool

    // MARK: - Initializers

    private init(
        name: String, height: CGFloat, fixedCornerRadius: CGFloat?, minimumSegmentWidth: CGFloat,
        dividerWidth: CGFloat, overflowButtonWidth: CGFloat, showsDividers: Bool, fillsSegments: Bool,
        trackFillOpacity: Double, trackBorderOpacity: Double, tintsSelection: Bool, selectionFillOpacity: Double,
        shrinksWithCrest: Bool
    ) {
        self.name = name
        self.height = height
        self.fixedCornerRadius = fixedCornerRadius
        self.minimumSegmentWidth = minimumSegmentWidth
        self.dividerWidth = dividerWidth
        self.overflowButtonWidth = overflowButtonWidth
        self.showsDividers = showsDividers
        self.fillsSegments = fillsSegments
        self.trackFillOpacity = trackFillOpacity
        self.trackBorderOpacity = trackBorderOpacity
        self.tintsSelection = tintsSelection
        self.selectionFillOpacity = selectionFillOpacity
        self.shrinksWithCrest = shrinksWithCrest
    }

    // MARK: - Actions - Drawing

    /// The corner radius of a part of the picker `height` tall: the compact
    /// radius, or for touch half the height, so every part is a capsule.
    /// `CrestSpaceIconPickerShape` draws every part with it.
    func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        fixedCornerRadius ?? height / 2
    }

    // MARK: - Actions - Sizing

    /// This style with segments sized for a crest drawn `scale` times its usual
    /// size. Segments always grow to hold a larger crest; they shrink with a
    /// smaller one only where `shrinksWithCrest`, so more Spaces fit across a
    /// pointer track while touch segments never fall below their own size.
    func scaled(by scale: CGFloat) -> CrestSpaceIconPickerStyle {
        let padding = CrestSpaceIconPickerMetrics.trackPadding
        let factor = shrinksWithCrest ? scale : max(1, scale)
        return CrestSpaceIconPickerStyle(
            name: name, height: (height - 2 * padding) * factor + 2 * padding,
            fixedCornerRadius: fixedCornerRadius, minimumSegmentWidth: minimumSegmentWidth * factor,
            dividerWidth: dividerWidth, overflowButtonWidth: overflowButtonWidth, showsDividers: showsDividers,
            fillsSegments: fillsSegments, trackFillOpacity: trackFillOpacity, trackBorderOpacity: trackBorderOpacity,
            tintsSelection: tintsSelection, selectionFillOpacity: selectionFillOpacity,
            shrinksWithCrest: shrinksWithCrest)
    }

    // MARK: - Actions - Identity

    static func == (lhs: CrestSpaceIconPickerStyle, rhs: CrestSpaceIconPickerStyle) -> Bool {
        lhs.name == rhs.name && lhs.height == rhs.height && lhs.minimumSegmentWidth == rhs.minimumSegmentWidth
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(height)
        hasher.combine(minimumSegmentWidth)
    }
}
