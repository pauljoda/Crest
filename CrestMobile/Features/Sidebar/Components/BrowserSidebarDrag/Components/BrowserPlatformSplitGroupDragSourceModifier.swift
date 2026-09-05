import SwiftUI
import UniformTypeIdentifiers

/// The iOS lift for a stacked split-group row.
///
/// Identical in shape to the tab row's mobile source, and for the same reason:
/// the row carries a context menu, and `UIContextMenuInteraction` cancels any
/// competing gesture the moment it claims the touch. Drag-and-drop is the one
/// path the system arbitrates against a context menu — holding still opens the
/// menu, pulling lifts the row.
///
/// The provider stages the shared lift, the drop feed supplies positions, and
/// the native source completes cancellation on every supported iOS version.
struct BrowserPlatformSplitGroupDragSourceModifier: ViewModifier {
    let item: BrowserSplitGroupDragItem
    /// The run this row stands for, used only to draw the lift preview.
    let members: [BrowserTab]
    let placement: TabPlacement
    let folderID: FolderID?
    let reorder: BrowserSidebarReorderContext

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: placement, folderID: folderID)
    }

    func body(content: Content) -> some View {
        content
            .browserSidebarReorderSource(
                item: .splitGroup(item),
                section: section,
                reorder: reorder
            )
            .browserMobileDraggable {
                reorder.state.stage(item: .splitGroup(item), section: section)
                let payload = (try? JSONEncoder().encode(item)) ?? Data()
                let provider = NSItemProvider(
                    item: payload as NSData,
                    typeIdentifier: UTType.json.identifier
                )
                let token = reorder.state.sessionToken
                return BrowserMobileDragSession(provider: provider) {
                    guard let token else { return }
                    reorder.state.cancel(session: token)
                }
            } preview: { _ in
                BrowserSplitGroupDragPreview(
                    members: members,
                    profileID: item.profileID
                )
            }
    }
}
