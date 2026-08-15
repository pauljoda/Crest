import SwiftUI

struct MobileArchiveView: View {
    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (TabID) -> Void

    var body: some View {
        MobileArchiveContent(
            space: space,
            restoreArchivedTab: restoreArchivedTab
        )
        .presentationDetents([.medium, .large])
    }

    private func restoreArchivedTab(_ tabID: TabID) {
        guard space != nil,
            browser.restoreArchivedTab(tabID, matching: assignment)
        else { return }
        selectTab(tabID)
    }

    private var space: BrowserSpace? {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        )
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    MobileArchiveView(
        browser: fixture.browser,
        assignment: BrowserSpaceRuntimeAssignment(space: fixture.space),
        spaceAccess: fixture.spaceAccess,
        selectTab: { _ in }
    )
}
