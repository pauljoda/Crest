import SwiftUI

struct PinnedTabDragModifier: ViewModifier {
    let tab: BrowserTab
    let assignment: BrowserSpaceRuntimeAssignment
    let moveTab: ((BrowserTabDragItem, TabID?) -> Bool)?
    let dragState: BrowserTabDragState?
    var reorder: BrowserSidebarReorderContext?

    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        if moveTab != nil, let dragState {
            content
                .browserTabDraggable(
                    tab: tab,
                    profileID: assignment.profileID,
                    spaceID: assignment.spaceID,
                    dragState: dragState,
                    reorder: reorder
                )
        } else {
            content
        }
    }
}
