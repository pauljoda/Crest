import CoreGraphics

/// The Space switcher's own measurements, kept apart from the segment geometry
/// that `BrowserSpacePickerMetrics` resolves.
///
/// The compact strip's numbers describe a control that has to sit inside a
/// windowed sidebar's foot alongside two utilities; the scrolling track's one
/// number describes the square a Space claims in a list a finger flicks
/// through.
enum BrowserSpaceSwitcherLayout {
    static let usesOneButtonPerSpace = true
    static let leadingUtility = BrowserSpaceSwitcherUtility.sidebarToggle
    static let trailingUtility = BrowserSpaceSwitcherUtility.commonLists
    static let showsSpaceCreation = false
    static let utilityButtonSize: CGFloat = 32
    static let segmentWidth = CrestSpaceIconPickerMetrics.segmentWidth
    static let segmentHeight = CrestSpaceIconPickerMetrics.segmentHeight
    static let cornerRadius = CrestSpaceIconPickerMetrics.cornerRadius

    /// The band the compact strip occupies, which is what holds the picker
    /// clear of the sidebar's bottom edge and the utilities either side of it.
    static let compactStripHeight: CGFloat = 50

    /// The inset that keeps the compact strip in the same column as the rows
    /// above it.
    static let compactStripHorizontalInset: CGFloat = 12

    /// The gap between the strip's utilities and the picker between them.
    static let compactStripSpacing: CGFloat = 2

    /// The square one Space claims in a scrolling track. It is both the
    /// segment's extent and the distance a flick steps by, so a gesture that
    /// crosses one segment lands on exactly one Space.
    static let scrollingSegmentExtent: CGFloat = 52

    /// The distance a drag has to travel before the track treats it as a step
    /// rather than as a scroll it should leave to the system.
    static let scrollingStepThreshold: CGFloat = 12

    /// The inset that lines the scrolling track up with the sidebar's rows,
    /// and the gap between it and the chrome above.
    static let scrollingTrackHorizontalInset: CGFloat = 12
    static let scrollingTrackTopInset: CGFloat = 6

    static func segmentIDs(for spaces: [BrowserSpace]) -> [SpaceID] {
        spaces.map(\.id)
    }
}
