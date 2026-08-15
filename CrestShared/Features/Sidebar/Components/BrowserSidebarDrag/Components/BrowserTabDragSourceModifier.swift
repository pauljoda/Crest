import SwiftUI

struct BrowserTabDragSourceModifier: ViewModifier {
    let tab: BrowserTab
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserTabDragState
    var reorder: BrowserSidebarReorderContext?
    var isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            let item = BrowserTabDragItem(
                tabID: tab.id,
                spaceID: spaceID,
                profileID: profileID
            )
            let isDragging = reorder == nil
                && BrowserTabDragVisualPolicy.usesPersistentSourceStyle(
                isDragging: dragState.isDragging(item),
                hasReliableTerminalLifecycle:
                    BrowserPlatformTabDragVisualPolicy.hasReliableTerminalLifecycle
            )
            content
                .scaleEffect(
                    BrowserTabDragVisualPolicy.sourceScale(isDragging: isDragging)
                )
                .opacity(
                    BrowserTabDragVisualPolicy.sourceOpacity(isDragging: isDragging)
                )
                .shadow(
                    color: .black.opacity(isDragging ? 0.24 : 0),
                    radius: BrowserTabDragVisualPolicy.sourceShadowRadius(
                        isDragging: isDragging
                    ),
                    y: BrowserTabDragVisualPolicy.sourceShadowYOffset(
                        isDragging: isDragging
                    )
                )
                .zIndex(isDragging ? 2 : 0)
                .animation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.dragSource,
                        reduceMotion: reduceMotion
                    ),
                    value: isDragging
                )
                .modifier(
                    BrowserPlatformTabDragSourceModifier(
                        tab: tab,
                        profileID: profileID,
                        spaceID: spaceID,
                        dragState: dragState,
                        reorder: reorder
                    )
                )
        } else {
            content
        }
    }
}

#Preview("Tab Drag Source Modifier", traits: .sizeThatFitsLayout) {
    let fixture = BrowserSidebarInteractionPreviewFixture()
    let dragState = fixture.makeTabDragState(tab: fixture.currentTab)

    Label(fixture.currentTab.displayTitle, systemImage: "doc.text.fill")
        .frame(width: 220, alignment: .leading)
        .padding(CrestSpacing.medium)
        .background(CrestColor.selectedSurface, in: .rect(cornerRadius: 10))
        .modifier(
            BrowserTabDragSourceModifier(
                tab: fixture.currentTab,
                profileID: fixture.space.profile.id,
                spaceID: fixture.space.id,
                dragState: dragState
            )
        )
        .padding()
}
