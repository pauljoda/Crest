import SwiftUI

struct BrowserPlatformFolderDragSourceModifier: ViewModifier {
    let folder: BrowserFolder
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserFolderDragState
    var memberTabIDs: [TabID]? = nil
    var reorder: BrowserSidebarReorderContext?

    private var item: BrowserFolderDragItem {
        BrowserFolderDragItem(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID,
            memberTabIDs: memberTabIDs
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
                    section: folder.reorderSection,
                    reorder: reorder,
                    registersContainer: false
                )
        } else {
            // No reorder context: previews and fixtures render a static row.
            content
        }
    }
}
