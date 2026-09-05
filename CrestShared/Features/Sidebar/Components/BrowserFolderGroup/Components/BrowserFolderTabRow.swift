import SwiftUI

/// A tab inside a saved folder: the sidebar's own row, indented to the
/// folder's depth.
struct BrowserFolderTabRow: View {
    let configuration: BrowserFolderGroupConfiguration
    let tab: BrowserTab
    let isLoaded: Bool
    var followingTabID: TabID? = nil
    var hasVisibleFollowingRow = false
    let unload: (TabID) -> Void

    var body: some View {
        BrowserSidebarTabRow(
            tab: tab,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID,
            isSelected: tab.id == configuration.selectedTabID,
            canClose: configuration.folder.location == .current,
            browser: configuration.browser,
            spaceAccess: configuration.spaceAccess,
            capabilities: configuration.capabilities,
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: pullNewIcon,
            restoreSavedLocation: restoreSavedLocation,
            promotionNamespace: configuration.promotionNamespace,
            followingTabID: followingTabID,
            hasVisibleFollowingRow: hasVisibleFollowingRow,
            select: configuration.select
        )
        .padding(.leading, configuration.rowLeadingInset)
    }

    /// Both actions are the host's to provide, so a row offers each one only
    /// where the host answered for it.
    private var pullNewIcon: (() -> Void)? {
        guard let action = configuration.pullNewIcon else { return nil }
        return { action(tab.id) }
    }

    private var restoreSavedLocation: (() -> Void)? {
        guard let action = configuration.restoreSavedLocation else { return nil }
        return { action(tab.id) }
    }
}
