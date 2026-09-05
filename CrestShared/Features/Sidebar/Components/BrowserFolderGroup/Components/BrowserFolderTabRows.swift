import SwiftUI

/// What the folder holds: every row while it is open, and the one tab it kept
/// on screen while it is closed.
///
/// This is the folder's own run, which is why the run's insertion line belongs
/// here rather than on the group. A closed folder answers a drop with the
/// nesting highlight on its header; an open one answers with the seam its rows
/// draw. An open folder holding nothing had neither — no row to hand the line
/// to, and no run for the line to stand in — so it took the tab in silence, and
/// the drag read as refused right up until it landed.
struct BrowserFolderTabRows: View {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext
    var displayedItems: [BrowserSidebarTabListItem]? = nil
    var followingTabIDsOverride: [TabID: TabID]? = nil

    private var items: [BrowserSidebarTabListItem] { displayedItems ?? configuration.items }

    private var keptCollapsedItem: BrowserSidebarTabListItem? {
        configuration.keptCollapsedItem(
            for: interaction.collapsedTabVisibility.wrappedValue
        )
    }

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: configuration.folder.location.tabPlacement, folderID: configuration.folder.id)
    }

    var body: some View {
        // Built once for the whole run rather than per row: it is a map over
        // every tab in the folder, and asking each row to rebuild it would
        // make drawing the folder quadratic in its own contents.
        let followingTabIDs = followingTabIDsOverride ?? configuration.followingTabIDs

        VStack(spacing: 0) {
            if interaction.isExpanded.wrappedValue {
                if items.isEmpty {
                    emptyRunBand
                } else {
                    rows(followingTabIDs: followingTabIDs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else if let keptCollapsedItem {
                collapsedRow(keptCollapsedItem)
                    .transition(.opacity)
            }
        }
        // The line is drawn across the run's own width, so the run has to claim
        // one even while it holds nothing.
        .frame(maxWidth: .infinity)

    }

    @ViewBuilder
    private func collapsedRow(_ item: BrowserSidebarTabListItem) -> some View {
        switch item {
        case .tab(let tab):
            BrowserFolderTabRow(
                configuration: configuration,
                tab: tab,
                isLoaded: true,
                followingTabID: nil,
                hasVisibleFollowingRow: false,
                unload: interaction.unloadKeptCollapsedTab
            )
        case .splitGroup(let groupID, let members):
            BrowserFolderSplitGroupRow(
                configuration: configuration,
                groupID: groupID,
                members: members,
                followingTabID: nil,
                hasVisibleFollowingRow: false
            )
        }
    }

    @ViewBuilder
    private func rows(followingTabIDs: [TabID: TabID]) -> some View {
        ForEach(items) { item in
            switch item {
            case .tab(let tab):
                let followingTabID = followingTabIDs[tab.id]
                BrowserFolderTabRow(
                    configuration: configuration,
                    tab: tab,
                    isLoaded: configuration.isLoaded(tab.id),
                    followingTabID: followingTabID,
                    hasVisibleFollowingRow: followingTabID != nil,
                    unload: { configuration.unload($0) }
                )
                // The identity a scroll aims at when a shell brings the
                // selected tab into view from inside a folder.
                .id(tab.id)
            case .splitGroup(let groupID, let members):
                let followingTabID = members.last.flatMap {
                    followingTabIDs[$0.id]
                }
                BrowserFolderSplitGroupRow(
                    configuration: configuration,
                    groupID: groupID,
                    members: members,
                    followingTabID: followingTabID,
                    hasVisibleFollowingRow: followingTabID != nil
                )
            }
        }
    }

    /// Where an open, empty folder's insertion line stands.
    ///
    /// It costs nothing at rest. The run is already reachable without a band of
    /// its own — the folder group's section zone spans the header, which is what
    /// lets a drop land in an open folder that has no rows to aim at — so this
    /// is only ever the line's canvas, never the target, and it opens only while
    /// there is a line to hold.
    private var emptyRunBand: some View {
        Color.clear
            .frame(height: emptyRunBandHeight)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }

    private var emptyRunBandHeight: CGFloat {
        let state = configuration.browser.sidebarReorderState
        guard !state.layout.isActive, state.emptySectionIndicator(for: section) != nil else { return 0 }
        let metrics =
            BrowserSidebarInteractionPolicy
            .tabListMetrics(configuration.capabilities)
        return metrics.sectionEndBandHeight
    }
}
