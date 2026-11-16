import CoreGraphics

/// The drawn geometry of a stacked split-group row, resolved once per shell
/// rather than spelled out by each row.
///
/// None of this describes a member. A group holds the *same* rows the tab list
/// draws everywhere else — full height, full favicon, full trailing control —
/// so a member's own geometry comes from `BrowserSidebarTabRowMetrics`, and
/// the header stands as a folder's does, from `BrowserFolderHeaderMetrics`.
/// What is left is how far apart the rows stack, and how large the stacked
/// icons draw.
///
/// The container's insets are deliberately absent here because they are not
/// the container's to choose. Its inset from the sidebar edge, the padding it
/// holds its rows in by, the space it keeps from its neighbours and its corners
/// are the ones a folder uses too, from `BrowserSidebarMetrics`, so a group
/// lines up in the same column as the tabs above and below it. The header's
/// leading inset is the tab row's `contentLeadingInset`, so the stacked icons
/// sit in a folder symbol's column.
struct BrowserSidebarSplitGroupRowMetrics: Equatable, Sendable {
    /// The gap between the header and the first member, and between members.
    ///
    /// A pointer shell stacks them flush: the rows are a fixed band each, and
    /// the container's own tint is what says they belong together. A touch
    /// shell separates them, because a finger aiming at one row in a stack of
    /// four wants to see where each one ends.
    let memberSpacing: CGFloat

    /// How large each card of the header's stacked icons draws, before the
    /// sidebar's density: a member favicon's size.
    let headerGlyphSize: CGFloat

    /// A pointer shell: members flush against one another.
    static let pointer = BrowserSidebarSplitGroupRowMetrics(
        memberSpacing: 0,
        headerGlyphSize: TabFaviconMetrics.defaultSize
    )

    /// A touch shell: the same container, with the members held apart and a
    /// slightly larger glyph, both read at arm's length rather than at a desk.
    static let touch = BrowserSidebarSplitGroupRowMetrics(
        memberSpacing: CrestSpacing.extraExtraSmall,
        headerGlyphSize: 20
    )
}
