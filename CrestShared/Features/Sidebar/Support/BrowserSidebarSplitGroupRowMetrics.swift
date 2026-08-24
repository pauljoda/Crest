import CoreGraphics

/// The drawn geometry of a stacked split-group row, resolved once per shell
/// rather than spelled out by each row.
///
/// None of this describes a member. A group holds the *same* rows the tab list
/// draws everywhere else — full height, full favicon, full trailing control —
/// so a member's own geometry comes from `BrowserSidebarTabRowMetrics`. What
/// is left is the container those rows sit in: how far it is held off the
/// sidebar's edge, how far the rows are held off its own, how far apart they
/// stack, and the slim strip above them that names the group.
///
/// Two of the container's insets are deliberately absent here because they are
/// not the container's to choose. Its inset from the sidebar edge is the tab
/// row's `surfaceHorizontalInset`, so a group lines up in the same column as
/// the tabs above and below it, and the header's leading inset is the tab
/// row's `contentLeadingInset`, so the count glyph sits in the same column as
/// the member favicons. Both are read from the tab row profile the same
/// capabilities resolve.
struct BrowserSidebarSplitGroupRowMetrics: Equatable, Sendable {
    /// Half the visible gutter between neighboring grouped surfaces, kept on
    /// the row so drag geometry includes the resting separation.
    let rowVerticalInset: CGFloat

    /// The inset between the container's edge and the rows inside it.
    let containerPadding: CGFloat

    /// Concentric with the rows inside: this radius less `containerPadding` is
    /// exactly `CrestLayout.sidebarControlCornerRadius`, so a focused member's
    /// corners stay parallel to the group's own.
    let containerCornerRadius: CGFloat

    /// The gap between the header and the first member, and between members.
    ///
    /// A pointer shell stacks them flush: the rows are a fixed band each, and
    /// the container's own tint is what says they belong together. A touch
    /// shell separates them, because a finger aiming at one row in a stack of
    /// four wants to see where each one ends.
    let memberSpacing: CGFloat

    /// The header owns group actions now, including its ellipsis menu. Touch
    /// shells therefore give it a full native hit target while pointer shells
    /// keep the compact sidebar rhythm.
    let headerHeight: CGFloat

    let headerGlyphSize: CGFloat

    let headerSpacing: CGFloat

    /// A pointer shell: members flush against one another under a compact
    /// header strip.
    static let pointer = BrowserSidebarSplitGroupRowMetrics(
        rowVerticalInset: CrestSpacing.extraExtraSmall,
        containerPadding: CrestSpacing.extraSmall,
        containerCornerRadius: CrestRadius.control,
        memberSpacing: 0,
        headerHeight: 30,
        headerGlyphSize: 16,
        headerSpacing: 7
    )

    /// A touch shell: the same container, with the members held apart and a
    /// slightly taller header carrying a slightly larger glyph, both read at
    /// arm's length rather than at a desk.
    static let touch = BrowserSidebarSplitGroupRowMetrics(
        rowVerticalInset: CrestSpacing.extraExtraSmall,
        containerPadding: CrestSpacing.extraSmall,
        containerCornerRadius: CrestRadius.control,
        memberSpacing: CrestSpacing.extraExtraSmall,
        headerHeight: 44,
        headerGlyphSize: 20,
        headerSpacing: 8
    )
}
