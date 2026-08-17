import SwiftUI

/// The macOS lift for a stacked split-group row.
///
/// Nothing beyond the in-view reorder source: a pointer `DragGesture` arms the
/// lift there, and the row itself is what travels under the cursor. The mobile
/// counterpart adds `.onDrag` because a finger has to share the touch with a
/// context menu; a pointer does not.
struct BrowserPlatformSplitGroupDragSourceModifier: ViewModifier {
    let item: BrowserSplitGroupDragItem
    /// Unused here. macOS draws the lift from the row's own view, so only the
    /// mobile source needs the run to build a drag preview from.
    let members: [BrowserTab]
    let placement: TabPlacement
    let folderID: FolderID?
    let reorder: BrowserSidebarReorderContext

    func body(content: Content) -> some View {
        content
            .browserSidebarReorderSource(
                item: .splitGroup(item),
                section: .tabs(placement: placement, folderID: folderID),
                reorder: reorder
            )
    }
}
