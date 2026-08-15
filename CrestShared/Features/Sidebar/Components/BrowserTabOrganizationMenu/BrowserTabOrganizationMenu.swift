import SwiftUI

struct BrowserTabOrganizationMenu: View {
    let tab: BrowserTab
    let assignment: BrowserTabRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var isLoaded = true
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: (() -> Void)? = nil
    var restoreSavedLocation: (() -> Void)? = nil
    var renameTab: (() -> Void)? = nil

    var body: some View {
        BrowserTabOrganizationMenuContent(menu: self)
    }
}

#Preview("Tab Organization Menu", traits: .sizeThatFitsLayout) {
    let fixture = BrowserSidebarInteractionPreviewFixture()

    Menu("Open Tab Actions", systemImage: "ellipsis.circle") {
        BrowserTabOrganizationMenu(
            tab: fixture.savedTab,
            assignment: fixture.tabAssignment,
            browser: fixture.browser,
            spaceAccess: fixture.spaceAccess,
            isLoaded: true,
            unload: { _ in },
            pullNewIcon: {},
            restoreSavedLocation: {},
            renameTab: {}
        )
    }
    .padding()
}
