import SwiftUI

struct MobileHistoryView: View {
    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceAccess: BrowserSpaceAccessController
    let openURL: (URL) -> Void

    var body: some View {
        MobileHistoryContent(
            space: space,
            clearHistory: clearHistory,
            openURL: openCapturedURL
        )
        .presentationDetents([.medium, .large])
    }

    private var space: BrowserSpace? {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        )
    }

    private func clearHistory() {
        guard space != nil else { return }
        browser.clearHistory(matching: assignment)
    }

    private func openCapturedURL(_ url: URL) {
        guard space != nil else { return }
        openURL(url)
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    MobileHistoryView(
        browser: fixture.browser,
        assignment: BrowserSpaceRuntimeAssignment(space: fixture.space),
        spaceAccess: fixture.spaceAccess,
        openURL: { _ in }
    )
}
