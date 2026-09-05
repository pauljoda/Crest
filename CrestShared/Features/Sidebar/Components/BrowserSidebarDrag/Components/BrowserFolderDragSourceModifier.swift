import SwiftUI

struct BrowserFolderDragSourceModifier: ViewModifier {
    let folder: BrowserFolder
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserFolderDragState
    var memberTabIDs: [TabID]? = nil
    var reorder: BrowserSidebarReorderContext?
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            let item = BrowserFolderDragItem(
                folderID: folder.id,
                spaceID: spaceID,
                profileID: profileID,
                memberTabIDs: memberTabIDs
            )
            let isDragging =
                reorder == nil
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
                        memberTabIDs: memberTabIDs,
                        reorder: reorder
                    )
                )
        } else {
            content
        }
    }
}
