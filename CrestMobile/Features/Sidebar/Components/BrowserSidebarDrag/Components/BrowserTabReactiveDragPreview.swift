import SwiftUI

struct BrowserTabReactiveDragPreview: View {
    let tab: BrowserTab
    let profileID: UUID
    let dragState: BrowserTabDragState
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowserTabDragPreview(
            tab: tab,
            profileID: profileID,
            progress: BrowserTabDragPreviewLayout.progress(
                for: dragState.currentPlacement ?? tab.placement
            )
        )
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.dragPreview,
                reduceMotion: reduceMotionOverride ?? reduceMotion
            ),
            value: dragState.currentPlacement
        )
    }
}
