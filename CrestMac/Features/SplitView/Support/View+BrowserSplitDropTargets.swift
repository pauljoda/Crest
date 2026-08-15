import SwiftUI

extension View {
    /// Offers this region as the place a dragged sidebar tab becomes a card.
    func browserSplitContentDropZone(
        assignment: BrowserSpaceRuntimeAssignment?,
        state: BrowserSidebarReorderState
    ) -> some View {
        modifier(
            BrowserSplitContentDropZoneModifier(
                assignment: assignment,
                state: state
            )
        )
    }

    /// Reports this region as one presented card, so a drop resolves against it.
    func browserSplitDropCardFrame(
        tabID: TabID?,
        state: BrowserSidebarReorderState
    ) -> some View {
        modifier(
            BrowserSplitDropCardFrameModifier(tabID: tabID, state: state)
        )
    }
}
