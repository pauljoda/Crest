import SwiftUI

struct SavedFolderTabRow: View {
    let configuration: SavedFolderGroupConfiguration
    let tab: BrowserTab
    let isLoaded: Bool
    let unload: (TabID) -> Void

    var body: some View {
        BrowserSidebarTabRow(
            tab: tab,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID,
            isSelected: tab.id == configuration.selectedTabID,
            canClose: false,
            browser: configuration.browser,
            spaceAccess: configuration.spaceAccess,
            capabilities: BrowserInteractionCapabilities(),
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: {
                configuration.pullNewIcon(for: tab.id)
            },
            restoreSavedLocation: {
                configuration.restoreSavedLocation(for: tab.id)
            },
            select: activate
        )
        .padding(.leading, configuration.rowLeadingInset)
    }

    /// Selection and presentation in the one order that works: the page a
    /// shell brings on screen is whichever one the session now points at.
    private func activate(_ tabID: TabID) {
        BrowserTabActivationPolicy.activate(
            tabID,
            selectTab: configuration.browser.selectTab,
            presentPage: {
                configuration.pages.select(session: configuration.browser.session)
            }
        )
    }
}
