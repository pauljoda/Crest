import CoreGraphics

/// A measured reorderable row. Frames are reported in global coordinates so rows
/// in different branches of the sidebar can be compared against one pointer.
struct BrowserSidebarReorderRow: Equatable, Sendable {
    let id: BrowserSidebarReorderItemID

    /// The Space whose run this row stands in.
    ///
    /// A section says only which run it is — `.tabs(placement: .pinned, …)` is
    /// *a* pinned grid, not whose. One reorder state serves every sidebar its
    /// store puts on screen, and more than one of them registers rows at a
    /// time: macOS opens several windows onto the same session, and every
    /// sidebar's Space pager keeps the pages either side of the visible one
    /// alive so a swipe can already show them. Rows from all of those land in
    /// one registry.
    ///
    /// Without the Space they land indistinguishably, and a drag then orders
    /// itself among rows nobody is dragging: insertion counts a neighbouring
    /// Space's tiles as already passed, and the pinned cap counts them as
    /// already filled — which is a grid that silently refuses every incoming
    /// pin while looking half empty.
    let space: BrowserSpaceRuntimeAssignment

    let section: BrowserSidebarReorderSection
    let frame: CGRect

    var usesGridOrdering: Bool {
        section.usesGridOrdering
    }
}
