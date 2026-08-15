import SwiftUI
import UniformTypeIdentifiers

struct SpacePickerSegment: View {
    let space: BrowserSpace
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        SpacePickerIcon(space: space, size: 24, lockSize: 6)
            .background(
                isDropTargeted
                    ? space.branding.primaryColor.color.opacity(0.24)
                    : .clear,
                in: .rect(cornerRadius: CrestRadius.compact)
            )
            .contentShape(.rect)
            .browserSidebarReorderZone(
                .space(assignment),
                state: browser.sidebarReorderState
            )
            .accessibilityHint("Select this Space, or drop a tab to move it here")
            .help(space.name)
    }

    private func moveTab(
        _ item: BrowserTabDragItem,
        to destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let moved = dragAction.move(item, into: destination)
        if moved {
            pages.select(session: browser.session)
        }
        return moved
    }

    private func selectDestination(
        _ item: BrowserTabDragItem,
        _ destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        dragAction.selectDestination(
            destination,
            for: item,
            using: selectSpace
        )
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    private var dragAction: BrowserTabDragAction {
        BrowserTabDragAction(browser: browser, spaceAccess: spaceAccess)
    }
}

#Preview("Space Picker Segment") {
    let preview = SpaceSwitcherPreviewFixture.makeContext()
    SpacePickerSegment(
        space: SpaceSwitcherPreviewFixture.firstSpace,
        browser: preview.browser,
        pages: preview.pages,
        spaceAccess: preview.spaceAccess,
        selectSpace: { _ in }
    )
    .padding()
}
