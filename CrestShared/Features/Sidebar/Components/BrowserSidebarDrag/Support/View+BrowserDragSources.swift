import SwiftUI

extension View {
    func browserTabDraggable(
        tab: BrowserTab,
        profileID: UUID,
        spaceID: SpaceID,
        dragState: BrowserTabDragState,
        reorder: BrowserSidebarReorderContext? = nil,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserTabDragSourceModifier(
                tab: tab,
                profileID: profileID,
                spaceID: spaceID,
                dragState: dragState,
                reorder: reorder,
                isEnabled: isEnabled
            )
        )
    }

    /// - Parameter members: the run behind this row, for platforms that draw
    ///   their own lift preview. macOS lifts the row itself and passes nothing.
    func browserSplitGroupDraggable(
        item: BrowserSplitGroupDragItem,
        members: [BrowserTab] = [],
        placement: TabPlacement,
        folderID: FolderID?,
        reorder: BrowserSidebarReorderContext? = nil,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserSplitGroupDragSourceModifier(
                item: item,
                members: members,
                placement: placement,
                folderID: folderID,
                reorder: reorder,
                isEnabled: isEnabled
            )
        )
    }

    func browserFolderDraggable(
        folder: BrowserFolder,
        profileID: UUID,
        spaceID: SpaceID,
        dragState: BrowserFolderDragState,
        memberTabIDs: [TabID]? = nil,
        reorder: BrowserSidebarReorderContext? = nil,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserFolderDragSourceModifier(
                folder: folder,
                profileID: profileID,
                spaceID: spaceID,
                dragState: dragState,
                memberTabIDs: memberTabIDs,
                reorder: reorder,
                isEnabled: isEnabled
            )
        )
    }
}
