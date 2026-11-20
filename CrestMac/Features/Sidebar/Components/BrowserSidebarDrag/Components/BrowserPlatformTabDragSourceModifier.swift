import SwiftUI

struct BrowserPlatformTabDragSourceModifier: ViewModifier {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let spaceID: UUID
    let dragState: BrowserTabDragState
    var reorder: BrowserSidebarReorderContext?
    var parentSplitGroupID: UUID?
    var isEnabled = true
    /// Whether the tab is the selected one. The window draws the Mac's lift
    /// from the sidebar's own selection, so this source reads none of it.
    var isTabSelected = false

    private var item: BrowserTabDragItem {
        BrowserTabDragItem(tabID: tab.id, spaceID: spaceID, profileID: profileID)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reorder {
            // The shared session moves rows; the window hosts the pointer preview.
            content
                .browserSidebarReorderSource(
                    item: .tab(item),
                    section: .tabs(
                        placement: tab.placement,
                        folderID: tab.folderID
                    ),
                    reorder: reorder,
                    parentItemID: parentSplitGroupID.map(BrowserSidebarReorderItemID.splitGroup),
                    isEnabled: isEnabled
                )
        } else {
            // No reorder context: previews and fixtures render a static row.
            content
        }
    }
}
