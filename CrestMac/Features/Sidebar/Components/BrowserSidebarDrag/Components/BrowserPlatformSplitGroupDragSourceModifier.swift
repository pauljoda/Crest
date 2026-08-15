import SwiftUI

/// The macOS lift for a stacked split-group row.
///
/// Nothing beyond the in-view reorder source: a pointer `DragGesture` arms the
/// lift there, and the row itself is what travels under the cursor. The mobile
/// counterpart adds `.onDrag` because a finger has to share the touch with a
/// context menu; a pointer does not.
struct BrowserPlatformSplitGroupDragSourceModifier: ViewModifier {
    let item: BrowserSplitGroupDragItem
    /// Unused here. macOS draws the lift from the row's own view, so only the
    /// mobile source needs the run to build a drag preview from.
    let members: [BrowserTab]
    let placement: TabPlacement
    let folderID: FolderID?
    let reorder: BrowserSidebarReorderContext

    func body(content: Content) -> some View {
        content
            .browserSidebarReorderSource(
                item: .splitGroup(item),
                section: .tabs(placement: placement, folderID: folderID),
                reorder: reorder
            )
    }
}

#Preview("Mac Split Group Drag Source", traits: .sizeThatFitsLayout) {
    let fixture = BrowserSidebarInteractionPreviewFixture()

    Label("Split View with 2 tabs", systemImage: "rectangle.split.2x1")
        .frame(width: 220, alignment: .leading)
        .padding(CrestSpacing.medium)
        .background(CrestColor.selectedSurface, in: .rect(cornerRadius: 10))
        .modifier(
            BrowserPlatformSplitGroupDragSourceModifier(
                item: BrowserSplitGroupDragItem(
                    groupID: SplitGroupID(),
                    spaceID: fixture.space.id,
                    profileID: fixture.space.profile.id,
                    memberTabIDs: [fixture.currentTab.id, fixture.savedTab.id]
                ),
                members: [fixture.currentTab, fixture.savedTab],
                placement: .current,
                folderID: nil,
                reorder: BrowserSidebarReorderContext(
                    browser: fixture.browser,
                    spaceAccess: fixture.spaceAccess
                )
            )
        )
        .padding()
}
