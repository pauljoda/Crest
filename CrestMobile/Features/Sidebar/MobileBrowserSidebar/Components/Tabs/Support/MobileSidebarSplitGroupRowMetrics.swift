import CoreGraphics

/// Geometry for the mobile stacked split-group row.
///
/// The macOS row shrinks its member lines so a group reads as one row rather
/// than several. A finger cannot do that: every member line keeps the full
/// `CrestLayout.sidebarRowHeight` touch target, and the group instead reads as
/// one thing through its container surface and the count affordance above the
/// lines.
enum MobileSidebarSplitGroupRowMetrics {
    /// Inset between the container's edge and its header and member lines.
    static let containerPadding: CGFloat = CrestSpacing.extraSmall

    static let containerCornerRadius = CrestRadius.control

    /// Concentric with the container: the outer radius less the inset, so a
    /// focused member's corners stay parallel to the group's own.
    static let memberCornerRadius = containerCornerRadius - containerPadding

    static let memberSpacing: CGFloat = CrestSpacing.extraExtraSmall

    /// Matches the tab row exactly — a member is still a 44pt touch target.
    static let memberLineHeight = CrestLayout.sidebarRowHeight

    static let accessibilityMemberLineHeight: CGFloat = 56

    /// The count affordance is a label, not a control, so it sits below the
    /// minimum hit target on purpose: nothing in it is tappable.
    static let headerHeight: CGFloat = 22

    static let headerGlyphSize: CGFloat = 11

    static let headerSpacing: CGFloat = 4

    /// Leading padding inside a member line, matching the tab row's own icon
    /// inset once the container padding is taken into account.
    static let memberLeadingInset =
        MobileSidebarRowLayoutPolicy.rootContentLeadingInset - containerPadding

    static let memberTrailingInset: CGFloat = 4

    static let memberContentSpacing: CGFloat = 4

    /// The row's own inset from the sidebar edge, matching
    /// `BrowserSidebarTabRow` so groups and tabs line up in the same column.
    static let rowHorizontalInset: CGFloat = 8

    /// Half the visible gutter between neighboring grouped surfaces. Keeping
    /// this on the row makes drag geometry include the resting separation.
    static let rowVerticalInset: CGFloat = CrestSpacing.extraExtraSmall

    static let closeControlSize = CGSize(width: 44, height: 44)

    static let closeGlyphSize: CGFloat = 14
}
