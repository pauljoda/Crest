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

#Preview("Reactive Tab Drag Preview", traits: .fixedLayout(width: 300, height: 160)) {
    let fixture = BrowserSidebarInteractionPreviewFixture()
    let currentDragState = fixture.makeTabDragState(tab: fixture.currentTab)
    let pinnedDragState = fixture.makeTabDragState(tab: fixture.pinnedTab)

    VStack(spacing: CrestSpacing.large) {
        BrowserTabReactiveDragPreview(
            tab: fixture.currentTab,
            profileID: fixture.space.profile.id,
            dragState: currentDragState
        )
        BrowserTabReactiveDragPreview(
            tab: fixture.pinnedTab,
            profileID: fixture.space.profile.id,
            dragState: pinnedDragState,
            reduceMotionOverride: true
        )
    }
    .padding()
}
