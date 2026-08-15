import CoreGraphics

/// A measured reorderable row. Frames are reported in global coordinates so rows
/// in different branches of the sidebar can be compared against one pointer.
struct BrowserSidebarReorderRow: Equatable, Sendable {
    let id: BrowserSidebarReorderItemID
    let section: BrowserSidebarReorderSection
    let frame: CGRect

    var usesGridOrdering: Bool {
        section.usesGridOrdering
    }
}
