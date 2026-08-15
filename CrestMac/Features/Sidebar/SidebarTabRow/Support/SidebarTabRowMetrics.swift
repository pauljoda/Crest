import CoreGraphics

/// Geometry the sidebar tab row owns, shared with the containers that nest it.
enum SidebarTabRowMetrics {
    /// The inset between a free-standing row's bounds and its interactive
    /// surface, which is what holds the surface off the sidebar's edge. A row
    /// nested in a split group drops it: the group's container padding has
    /// already placed the row, and applying both would leave the member
    /// noticeably narrower than the tabs above and below the group.
    static let surfaceHorizontalInset: CGFloat = 8
}
