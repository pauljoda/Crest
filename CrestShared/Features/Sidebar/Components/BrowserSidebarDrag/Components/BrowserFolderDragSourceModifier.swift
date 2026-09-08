import SwiftUI

struct BrowserFolderDragSourceModifier: ViewModifier {
    let folder: BrowserFolder
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserFolderDragState
    var memberTabIDs: [TabID]? = nil
    var reorder: BrowserSidebarReorderContext?
    let isEnabled: Bool
    var requiresSelectedSpace = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    @ViewBuilder
    func body(content: Content) -> some View {
        let isEnabled = SidebarSpaceRole.permitsInteraction(
            isSelected: requiresSelectedSpace ? isSelected : nil, isAvailable: self.isEnabled)
        let item = BrowserFolderDragItem(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID,
            memberTabIDs: memberTabIDs
        )
        let isDragging =
            isEnabled && reorder == nil
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
                    reorder: reorder,
                    isEnabled: isEnabled
                )
            )
    }
}
