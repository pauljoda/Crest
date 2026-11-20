import SwiftUI

struct PinnedTabDragModifier: ViewModifier {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let assignment: BrowserSpaceRuntimeAssignment
    let dragState: BrowserTabDragState?
    var reorder: BrowserSidebarReorderContext?
    /// Whether the pin is the selected one, whose lift stays on paper.
    var isSelected = false

    func body(content: Content) -> some View {
        if let reorder, let dragState {
            content
                .browserTabDraggable(
                    tab: tab,
                    favicons: favicons,
                    profileID: assignment.profileID,
                    spaceID: assignment.spaceID,
                    dragState: dragState,
                    reorder: reorder,
                    isTabSelected: isSelected
                )
        } else {
            content
        }
    }
}
