import SwiftUI

/// Shared measurements for the compact Space icon picker.
enum CrestSpaceIconPickerMetrics {
    static let segmentWidth: CGFloat = 40
    static let segmentHeight: CGFloat = 30
    static let cornerRadius: CGFloat = CrestRadius.compact
    static let trackPadding: CGFloat = 3
    /// How far the selector sits inside a group's highlight: the track's
    /// padding, so the two keep concentric corners.
    static let groupSelectionInset: CGFloat = trackPadding
    static let overflowButtonWidth: CGFloat = 28
}

/// Styling changes with input size; selection, overflow and actions are shared.
struct CrestSpaceIconPickerStyle: Hashable, Sendable {
    // MARK: - Static Variables

    static let compact = CrestSpaceIconPickerStyle(
        name: "compact",
        height: CrestSpaceIconPickerMetrics.segmentHeight + 2 * CrestSpaceIconPickerMetrics.trackPadding,
        trackPadding: CrestSpaceIconPickerMetrics.trackPadding,
        segmentCornerRadius: CrestSpaceIconPickerMetrics.cornerRadius,
        minimumSegmentWidth: CrestSpaceIconPickerMetrics.segmentWidth, smallestSegment: .zero,
        overflowButtonWidth: CrestSpaceIconPickerMetrics.overflowButtonWidth, fillsSegments: false)
    /// How wide a dot's segment is under a pointer, and under a finger.
    private static let pointerDotSegmentWidth: CGFloat = 16
    private static let touchDotSegmentWidth: CGFloat = 26
    static let touch = CrestSpaceIconPickerStyle(
        name: "touch", height: 48, trackPadding: CrestSpaceIconPickerMetrics.trackPadding, segmentCornerRadius: nil,
        minimumSegmentWidth: 52, smallestSegment: CGSize(width: 44, height: 42), overflowButtonWidth: 44,
        fillsSegments: true)

    // MARK: - Variables

    let name: String
    private(set) var height: CGFloat

    /// The clearance between the track's edge and the segments inside it.
    private(set) var trackPadding: CGFloat

    /// The corner radius of a Space's segment, which the selector on its own
    /// takes, or `nil` for a capsule. Every other part's corners follow it
    /// concentrically.
    private(set) var segmentCornerRadius: CGFloat?

    private(set) var minimumSegmentWidth: CGFloat

    /// The smallest a segment gets however small its crest is drawn. Touch
    /// keeps its full height and the width a finger needs; a pointer's
    /// segments shrink with their crests.
    private(set) var smallestSegment: CGSize

    let overflowButtonWidth: CGFloat

    /// Whether the segments widen to share the whole width the picker has.
    private(set) var fillsSegments: Bool

    /// The height of one segment inside the track.
    var segmentHeight: CGFloat {
        height - 2 * trackPadding
    }

    // MARK: - Initializers

    private init(
        name: String, height: CGFloat, trackPadding: CGFloat, segmentCornerRadius: CGFloat?,
        minimumSegmentWidth: CGFloat, smallestSegment: CGSize, overflowButtonWidth: CGFloat, fillsSegments: Bool
    ) {
        self.name = name
        self.height = height
        self.trackPadding = trackPadding
        self.segmentCornerRadius = segmentCornerRadius
        self.minimumSegmentWidth = minimumSegmentWidth
        self.smallestSegment = smallestSegment
        self.overflowButtonWidth = overflowButtonWidth
        self.fillsSegments = fillsSegments
    }

    // MARK: - Actions - Drawing

    /// The corner radius of a part of the picker `height` tall, concentric
    /// with a segment's: the segment's radius grown by however far the part
    /// reaches past a segment on each side, as the well does by its padding,
    /// or shrunk by however far it sits inside, as the selector inside a
    /// group's highlight does. A capsule's parts stay capsules.
    /// `CrestSpaceIconPickerShape` draws every part with it.
    func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        let segment = min(segmentCornerRadius ?? segmentHeight / 2, segmentHeight / 2)
        return min(height / 2, max(0, segment + (height - segmentHeight) / 2))
    }

    /// This style with segments whose corners have `radius`, the corner
    /// radius Crest's tabs and pins take, a capsule at most.
    func rounded(_ radius: CGFloat) -> CrestSpaceIconPickerStyle {
        var style = self
        style.segmentCornerRadius = radius >= segmentHeight / 2 ? nil : max(0, radius)
        return style
    }

    // MARK: - Actions - Sizing

    /// This style with segments sized for a crest drawn `scale` times its
    /// usual size, down to `smallestSegment`.
    ///
    /// The track's padding and corners follow the segment's height, so a
    /// smaller track keeps the shape of the full-size one rather than rounding
    /// off. Segments come out an even number of points each way and the
    /// padding a whole one, so a track of any size, and the crests centred in
    /// it, centre on the same point as the controls beside it.
    func scaled(by scale: CGFloat) -> CrestSpaceIconPickerStyle {
        let segmentHeight = max(smallestSegment.height, Self.evenPoints(self.segmentHeight * scale))
        let shape = segmentHeight / self.segmentHeight
        var style = self
        style.trackPadding = (trackPadding * shape).rounded()
        style.height = segmentHeight + 2 * style.trackPadding
        style.segmentCornerRadius = segmentCornerRadius.map { $0 * shape }
        style.minimumSegmentWidth = max(smallestSegment.width, Self.evenPoints(minimumSegmentWidth * scale))
        return style
    }

    /// This style for dots: narrow segments packed together in the middle,
    /// a pointer's as wide as a dot's room and a finger's a little wider.
    func dotted() -> CrestSpaceIconPickerStyle {
        var style = self
        let width = smallestSegment.width > 0 ? Self.touchDotSegmentWidth : Self.pointerDotSegmentWidth
        style.minimumSegmentWidth = width
        style.smallestSegment.width = min(smallestSegment.width, width)
        style.fillsSegments = false
        return style
    }

    /// `length` to the nearest even number of points.
    private static func evenPoints(_ length: CGFloat) -> CGFloat {
        2 * (length / 2).rounded()
    }

    /// How wide the track is with `spaceCount` Spaces side by side at their
    /// narrowest.
    func contentWidth(spaceCount: Int) -> CGFloat {
        guard spaceCount > 0 else { return 0 }
        return 2 * trackPadding + CGFloat(spaceCount) * minimumSegmentWidth
    }

    // MARK: - Actions - Identity

    static func == (lhs: CrestSpaceIconPickerStyle, rhs: CrestSpaceIconPickerStyle) -> Bool {
        lhs.name == rhs.name && lhs.height == rhs.height && lhs.minimumSegmentWidth == rhs.minimumSegmentWidth
            && lhs.segmentCornerRadius == rhs.segmentCornerRadius
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(height)
        hasher.combine(minimumSegmentWidth)
        hasher.combine(segmentCornerRadius)
    }
}

/// How a Space picker's surfaces show over a sidebar: a well recessed into
/// it, in black, the segments sit in; a soft highlight, in white, across the
/// group of Sub-Spaces the shown Space belongs to; and a brighter selector,
/// in white, on the shown Space, stacked inside that highlight. Over a dark
/// sidebar, whose text reads light, the well deepens and the highlights stay
/// faint; over a light one the well is a shade and the highlights near white.
struct CrestSpaceIconPickerTone: Equatable, Sendable {
    // MARK: - Static Variables

    static let onDark = CrestSpaceIconPickerTone(well: 0.22, group: 0.09, selector: 0.22)
    static let onLight = CrestSpaceIconPickerTone(well: 0.07, group: 0.4, selector: 0.85)

    // MARK: - Variables

    /// How strongly the black well shows.
    let well: Double
    /// How strongly the white highlight across a group shows.
    let group: Double
    /// How strongly the white selector shows.
    let selector: Double

    var wellColor: Color { .black.opacity(well) }
    var groupColor: Color { .white.opacity(group) }
    var selectorColor: Color { .white.opacity(selector) }

    // MARK: - Initializers

    private init(well: Double, group: Double, selector: Double) {
        self.well = well
        self.group = group
        self.selector = selector
    }

    // MARK: - Functions

    /// The tone over a sidebar whose text reads in `scheme`'s colors: dark,
    /// so light text, or light.
    static func over(_ scheme: ColorScheme) -> CrestSpaceIconPickerTone {
        scheme == .dark ? .onDark : .onLight
    }

    /// The tone `darkness` of the way from a light sidebar's to a dark one's,
    /// for a selection moving between Spaces of both.
    static func between(darkness: Double) -> CrestSpaceIconPickerTone {
        func mix(_ light: Double, _ dark: Double) -> Double { light + (dark - light) * darkness }
        return CrestSpaceIconPickerTone(
            well: mix(onLight.well, onDark.well), group: mix(onLight.group, onDark.group),
            selector: mix(onLight.selector, onDark.selector))
    }
}
