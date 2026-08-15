import SwiftUI
import UniformTypeIdentifiers

struct MobileSpacePickerSegment: View {
    let space: BrowserSpace
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        MobileSpacePickerIcon(space: space)
            .opacity(isDropTargeted ? 0.72 : 1)
            .browserSidebarReorderZone(
                .space(assignment),
                state: browser.sidebarReorderState
            )
            .accessibilityHint("Select this Space, or drop a tab to move it here")
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

#Preview("Mobile Space Picker Segment", traits: .sizeThatFitsLayout) {
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileSpacePickerSegment(
        space: fixture.protectedSpace,
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        selectSpace: { _ in }
    )
    .padding()
}
