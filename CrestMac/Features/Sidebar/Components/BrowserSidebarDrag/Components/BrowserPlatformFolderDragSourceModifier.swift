import SwiftUI

struct BrowserPlatformFolderDragSourceModifier: ViewModifier {
    let folder: SavedFolder
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserFolderDragState
    var reorder: BrowserSidebarReorderContext?

    private var item: BrowserFolderDragItem {
        BrowserFolderDragItem(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reorder {
            // Folders reorder in place among their siblings, on the same path as
            // tabs. See `BrowserSidebarReorderState` for why AppKit's dragging
            // session is not used.
            content
                .browserSidebarReorderSource(
                    item: .folder(item),
                    section: .folders(parentID: folder.parentID),
                    reorder: reorder
                )
        } else {
            // No reorder context: previews and fixtures render a static row.
            content
        }
    }
}
