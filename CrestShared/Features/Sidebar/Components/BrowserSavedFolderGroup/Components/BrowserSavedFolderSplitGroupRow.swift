import SwiftUI

/// A split group inside a saved folder, indented to the folder's depth exactly
/// like the tab rows beside it.
struct BrowserSavedFolderSplitGroupRow: View {
    let configuration: BrowserSavedFolderGroupConfiguration
    let groupID: SplitGroupID
    let members: [BrowserTab]
    var followingTabID: TabID? = nil
    var hasVisibleFollowingRow = false

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
            capabilities: configuration.capabilities,
            isLoaded: { configuration.isLoaded($0) },
            unload: { configuration.unload($0) },
            pullNewIcon: configuration.pullNewIcon,
            restoreSavedLocation: configuration.restoreSavedLocation,
            promotionNamespace: configuration.promotionNamespace,
            followingTabID: followingTabID,
            hasVisibleFollowingRow: hasVisibleFollowingRow,
            select: configuration.select
        )
        .padding(.leading, configuration.rowLeadingInset)
    }
}
