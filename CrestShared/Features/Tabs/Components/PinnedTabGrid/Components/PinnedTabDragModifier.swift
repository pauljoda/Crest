import SwiftUI

struct PinnedTabDragModifier: ViewModifier {
    let tab: BrowserTab
    let assignment: BrowserSpaceRuntimeAssignment
    let moveTab: ((BrowserTabDragItem, TabID?) -> Bool)?
    let dragState: BrowserTabDragState?
    var reorder: BrowserSidebarReorderContext?

    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        if let moveTab, let dragState {
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

#Preview("Pinned Tab Drag Modifier", traits: .sizeThatFitsLayout) {
    let fixture = PinnedTabGridPreviewFixture()
    let dragState = fixture.makeTabDragState()

    Label(fixture.pinnedTab.displayTitle, systemImage: "square.grid.2x2.fill")
        .padding(CrestSpacing.medium)
        .background(CrestColor.selectedSurface, in: .rect(cornerRadius: 10))
        .modifier(
            PinnedTabDragModifier(
                tab: fixture.pinnedTab,
                assignment: fixture.assignment,
                moveTab: { _, _ in true },
                dragState: dragState
            )
        )
        .padding()
}
