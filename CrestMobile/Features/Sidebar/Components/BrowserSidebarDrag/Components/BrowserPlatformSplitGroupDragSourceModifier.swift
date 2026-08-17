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
/// Three pieces have to line up, and each one broke the interaction on its own
/// when it did not:
///
/// 1. The `.onDrag` provider only *stages* the lift. It runs at the press,
///    before any session exists; beginning the lift here would hide the row
///    while nothing is in flight, and a press released without pulling produces
///    no session to clear it.
/// 2. `BrowserSidebarReorderDropDelegate` promotes the stage on its first
///    position — that sample is the proof a drag is genuinely under way.
/// 3. `BrowserMobileReorderSessionModifier` clears a session that ends away
///    from the sidebar, so the row is hidden only while genuinely lifted.
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
            .onDrag {
                reorder.state.stage(item: .splitGroup(item), section: section)
                let payload = (try? JSONEncoder().encode(item)) ?? Data()
                return NSItemProvider(
                    item: payload as NSData,
                    typeIdentifier: UTType.json.identifier
                )
            } preview: {
                BrowserSplitGroupDragPreview(
                    members: members,
                    profileID: item.profileID
                )
            }
            .modifier(
                BrowserMobileReorderSessionModifier(state: reorder.state)
            )
    }
}
