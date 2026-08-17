import CoreGraphics

/// Geometry for the stacked split-group row.
///
/// A group holds the *same* rows the tab list draws everywhere else — full
/// height, full favicon, full trailing control — so none of this describes a
/// member. It describes the container those rows sit in: how far its surface
/// is held off the sidebar's edge, how far the rows are held off its own, and
/// the slim strip above them that names the group.
enum SidebarSplitGroupRowMetrics {
    /// The container's inset from the sidebar edge, matching the inset
    /// `SidebarTabRow` gives its own surface so a group lines up in the same
    /// column as the tabs above and below it.
    static let rowHorizontalInset = SidebarTabRowMetrics.surfaceHorizontalInset

    /// Half the visible gutter between neighboring grouped surfaces. This
    /// mirrors the mobile row so two adjacent Split Views remain distinct.
    static let rowVerticalInset: CGFloat = CrestSpacing.extraExtraSmall

    /// Inset between the container's edge and the rows inside it.
    static let containerPadding: CGFloat = CrestSpacing.extraSmall

    /// Concentric with the rows inside: this radius less `containerPadding` is
    /// exactly `CrestLayout.sidebarControlCornerRadius`, so a focused member's
    /// corners stay parallel to the group's own.
    static let containerCornerRadius = CrestRadius.control

    /// The count affordance is a label, not a control, so it sits below the
    /// minimum hit target on purpose: nothing in it is clickable, and the
    /// group's own context menu is what a right-click there reaches.
    static let headerHeight: CGFloat = 20

    static let headerGlyphSize: CGFloat = 10

    static let headerSpacing: CGFloat = 4

    /// Puts the header's glyph in the same column as the member rows' favicons:
    /// the tab row's label carries this same leading inset, and both sit inside
    /// `containerPadding`.
    static let headerLeadingInset: CGFloat = 9
}
