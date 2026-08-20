import SwiftUI

/// What the folder holds: every row while it is open, and the one tab it kept
/// on screen while it is closed.
struct BrowserSavedFolderTabRows: View {
    let configuration: BrowserSavedFolderGroupConfiguration
    let interaction: BrowserSavedFolderGroupInteractionContext

    private var keptCollapsedTab: BrowserTab? {
        configuration.keptCollapsedTab(
            for: interaction.collapsedTabVisibility.wrappedValue
        )
    }

    var body: some View {
        // Built once for the whole run rather than per row: it is a map over
        // every tab in the folder, and asking each row to rebuild it would
        // make drawing the folder quadratic in its own contents.
        let followingTabIDs = configuration.followingTabIDs

        Group {
            if interaction.isExpanded.wrappedValue {
                ForEach(configuration.items) { item in
                    switch item {
                    case .tab(let tab):
                        let followingTabID = followingTabIDs[tab.id]
                        BrowserSavedFolderTabRow(
                            configuration: configuration,
                            tab: tab,
                            isLoaded: configuration.isLoaded(tab.id),
                            followingTabID: followingTabID,
                            hasVisibleFollowingRow: followingTabID != nil,
                            unload: { configuration.unload($0) }
                        )
                        // The identity a scroll aims at when a shell brings
                        // the selected tab into view from inside a folder.
                        .id(tab.id)
                    case .splitGroup(let groupID, let members):
                        let followingTabID = members.last.flatMap {
                            followingTabIDs[$0.id]
                        }
                        BrowserSavedFolderSplitGroupRow(
                            configuration: configuration,
                            groupID: groupID,
                            members: members,
                            followingTabID: followingTabID,
                            hasVisibleFollowingRow: followingTabID != nil
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let keptCollapsedTab {
                BrowserSavedFolderTabRow(
                    configuration: configuration,
                    tab: keptCollapsedTab,
                    isLoaded: true,
                    followingTabID: followingTabIDs[keptCollapsedTab.id],
                    hasVisibleFollowingRow: false,
                    unload: interaction.unloadKeptCollapsedTab
                )
                .transition(.opacity)
            }
        }
    }
}
