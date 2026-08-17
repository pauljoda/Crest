import SwiftUI
import UniformTypeIdentifiers

struct BrowserPlatformFolderDragSourceModifier: ViewModifier {
    let folder: SavedFolder
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserFolderDragState
    var reorder: BrowserSidebarReorderContext?

    @State private var sessionToken: BrowserDragSessionToken?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reorder {
            // As with tabs: the lift comes from drag-and-drop so it can coexist
            // with the row's context menu.
            let item = BrowserFolderDragItem(
                folderID: folder.id,
                spaceID: spaceID,
                profileID: profileID
            )
            content
                .browserSidebarReorderSource(
                    item: .folder(item),
                    section: .folders(parentID: folder.parentID),
                    reorder: reorder
                )
                .onDrag {
                    reorder.state.stage(
                        item: .folder(item),
                        section: .folders(parentID: folder.parentID)
                    )
                    let payload = (try? JSONEncoder().encode(item)) ?? Data()
                    return NSItemProvider(
                        item: payload as NSData,
                        typeIdentifier: UTType.json.identifier
                    )
                } preview: {
                    BrowserFolderDragPreview(folder: folder)
                }
                .modifier(
                    BrowserMobileReorderSessionModifier(state: reorder.state)
                )
        } else {
            legacyDraggable(content)
        }
    }

    @ViewBuilder
    private func legacyDraggable(_ content: Content) -> some View {
        let draggableContent =
            content
            .onDrag {
                let item = BrowserFolderDragItem(
                    folderID: folder.id,
                    spaceID: spaceID,
                    profileID: profileID
                )
                sessionToken = dragState.begin(item: item)
                let data = (try? JSONEncoder().encode(item)) ?? Data()
                return NSItemProvider(
                    item: data as NSData,
                    typeIdentifier: UTType.json.identifier
                )
            } preview: {
                BrowserFolderDragPreview(folder: folder)
            }

        #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                draggableContent
                    .onDragSessionUpdated { session in
                        let lifecyclePhase: BrowserTabDragSessionLifecyclePhase =
                            switch session.phase {
                            case .ended:
                                .ended
                            case .dataTransferCompleted:
                                .dataTransferCompleted
                            default:
                                .active
                            }
                        guard
                            BrowserTabDragSessionLifecyclePolicy.shouldEnd(
                                for: lifecyclePhase
                            )
                        else { return }
                        Task { @MainActor in
                            guard let sessionToken else { return }
                            dragState.end(session: sessionToken)
                        }
                    }
            } else {
                draggableContent
            }
        #else
            draggableContent
        #endif
    }
}
