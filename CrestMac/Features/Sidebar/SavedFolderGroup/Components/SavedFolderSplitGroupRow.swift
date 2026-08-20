import SwiftUI

/// A split group inside a saved folder, indented to the folder's depth exactly
/// like the tab rows beside it.
struct SavedFolderSplitGroupRow: View {
    let configuration: SavedFolderGroupConfiguration
    let groupID: SplitGroupID
    let members: [BrowserTab]

    var body: some View {
        BrowserSidebarSplitGroupRow(
            groupID: groupID,
            members: members,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID,
            selectedTabID: configuration.selectedTabID,
            canClose: false,
            browser: configuration.browser,
            spaceAccess: configuration.spaceAccess,
            capabilities: BrowserInteractionCapabilities(),
            isLoaded: { configuration.pages.containsResidentPage(for: $0) },
            unload: { tabID in
                configuration.pages.unloadPage(
                    for: tabID,
                    matching: configuration.assignment
                )
            },
            pullNewIcon: { tabID in
                configuration.tabActions.pullNewIcon(for: tabID)
            },
            restoreSavedLocation: { tabID in
                configuration.tabActions.restoreSavedLocation(for: tabID)
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
