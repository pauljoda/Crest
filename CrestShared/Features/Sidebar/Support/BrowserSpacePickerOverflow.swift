import CoreGraphics

/// Only changes when another Space becomes hidden or an edge is reached.
struct BrowserSpacePickerOverflow: Equatable {
    var previousIndex: Int?
    var nextIndex: Int?

    init() {}

    init(
        visibleRect: CGRect, contentWidth: CGFloat, spaceCount: Int,
        segmentWidth: CGFloat = BrowserSpaceSwitcherLayout.segmentWidth,
        dividerWidth: CGFloat = CrestLayout.hairline
    ) {
        guard spaceCount > 0 else { return }
        let padding = CrestSpaceIconPickerMetrics.trackPadding
        let stride = segmentWidth + dividerWidth
        if visibleRect.minX > 0.5 {
            previousIndex = min(spaceCount - 1, max(0, Int(floor((visibleRect.minX - padding) / stride))))
        }
        if visibleRect.maxX < contentWidth - 0.5 {
            nextIndex = min(spaceCount - 1, max(0, Int(floor((visibleRect.maxX - padding) / stride))))
        }
    }
}
