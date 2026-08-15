import SwiftUI

struct MobileFolderLiveDropDelegate: DropDelegate {
    let location: BrowserTabDropLocation
    let dragState: BrowserTabDragState
    let folderLocation: BrowserFolderDropLocation
    let folderDragState: BrowserFolderDragState
    @Binding var isTargeted: Bool
    let move: (BrowserTabDragItem, TabID?) -> Bool
    let moveFolder: (BrowserFolderDragItem, BrowserFolderDropLocation) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        if let folderItem = folderDragState.item {
            return folderItem.folderID != folderLocation.beforeSiblingID
        }
        return dragState.item != nil
    }

    func dropEntered(info: DropInfo) {
        guard dragState.item != nil || folderDragState.item != nil else { return }
        isTargeted = true
        if dragState.item != nil {
            _ = dragState.enter(location)
        } else {
            _ = folderDragState.enter(folderLocation)
        }
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        #if os(iOS)
            dragState.deferLeave(location)
        #else
            dragState.leave(location)
        #endif
        folderDragState.leave(folderLocation)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            isTargeted = false
            dragState.end()
            folderDragState.end()
        }
        if let folderItem = folderDragState.item {
            return moveFolder(folderItem, folderLocation)
        }
        guard let item = dragState.item else { return false }
        return move(item, location.beforeTabID)
    }
}
