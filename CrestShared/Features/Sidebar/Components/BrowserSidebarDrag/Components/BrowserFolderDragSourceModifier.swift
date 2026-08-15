import SwiftUI

struct BrowserFolderDragSourceModifier: ViewModifier {
    let folder: SavedFolder
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserFolderDragState
    var reorder: BrowserSidebarReorderContext?
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            let item = BrowserFolderDragItem(
                folderID: folder.id,
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
                    BrowserPlatformFolderDragSourceModifier(
                        folder: folder,
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

#Preview("Folder Drag Source Modifier", traits: .sizeThatFitsLayout) {
    let fixture = BrowserSidebarInteractionPreviewFixture()
    let dragState = fixture.makeFolderDragState()

    Label(fixture.folder.title, systemImage: fixture.folder.symbol)
        .frame(width: 220, alignment: .leading)
        .padding(CrestSpacing.medium)
        .background(CrestColor.selectedSurface, in: .rect(cornerRadius: 10))
        .modifier(
            BrowserFolderDragSourceModifier(
                folder: fixture.folder,
                profileID: fixture.space.profile.id,
                spaceID: fixture.space.id,
                dragState: dragState,
                isEnabled: true
            )
        )
        .padding()
}
