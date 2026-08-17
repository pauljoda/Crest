import SwiftUI

struct BrowserPlatformTabDragSourceModifier: ViewModifier {
    let tab: BrowserTab
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserTabDragState
    var reorder: BrowserSidebarReorderContext?

    private var item: BrowserTabDragItem {
        BrowserTabDragItem(tabID: tab.id, spaceID: spaceID, profileID: profileID)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reorder {
            // Reordering happens in our own view tree: the row's slot opens, its
            // neighbours step aside, and the preview that chases the pointer —
            // morphing toward the tile or the card the drop would make of it — is
            // drawn above the window. See `BrowserSidebarReorderState` for why
            // AppKit's dragging session is not used, and `floatingLift` there for
            // why the preview does not live in this view tree.
            content
                .browserSidebarReorderSource(
                    item: .tab(item),
                    section: .tabs(
                        placement: tab.placement,
                        folderID: tab.folderID
                    ),
                    reorder: reorder
                )
        } else {
            // No reorder context: previews and fixtures render a static row.
            content
        }
    }
}
