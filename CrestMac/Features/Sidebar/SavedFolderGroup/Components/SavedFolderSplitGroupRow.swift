import SwiftUI

/// A split group inside a saved folder, indented to the folder's depth exactly
/// like the tab rows beside it.
struct SavedFolderSplitGroupRow: View {
    let configuration: SavedFolderGroupConfiguration
    let groupID: SplitGroupID
    let members: [BrowserTab]

    var body: some View {
        SidebarSplitGroupRow(
            groupID: groupID,
            members: members,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID,
            selectedTabID: configuration.selectedTabID,
            canClose: false,
            browser: configuration.browser,
            spaceAccess: configuration.spaceAccess,
            presentSelectedPage: {
                configuration.pages.select(session: configuration.browser.session)
            },
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
            }
        )
        .padding(.leading, configuration.rowLeadingInset)
    }
}
