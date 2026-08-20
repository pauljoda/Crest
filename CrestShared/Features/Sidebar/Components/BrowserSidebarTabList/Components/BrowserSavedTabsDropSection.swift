import SwiftUI

/// The Space's saved tabs as one drop section, on every shell: its folder groups
/// and, below them, the saved tabs that are in no folder.
///
/// The unfiled tabs are kept as a run of their own so the drop feedback for that
/// run has somewhere to appear. The folder groups above share this section's
/// zone, and the unfiled rows land below them.
struct BrowserSavedTabsDropSection: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let pageAccess: BrowserSidebarPageAccess
    let tabActions: BrowserSidebarTabActions
    let capabilities: BrowserInteractionCapabilities
    var promotionNamespace: Namespace.ID? = nil
    /// How a saved tab gets back to the page it was saved from. The two shells
    /// answer that differently, so the host binds it.
    let restoreSavedLocation: (TabID) -> Void
    /// What opening a tab means to the host. The rows decide *whether*; the host
    /// decides what appears.
    let select: (TabID) -> Void
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: .saved, folderID: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(folderNodes) { node in
                BrowserSavedFolderGroup(
                    node: node,
                    tabs: tabSections.savedTabs(in: node.id),
                    spaceID: space.id,
                    profileID: space.profile.id,
                    selectedTabID: space.selectedTabID,
                    browser: browser,
                    pageAccess: pageAccess,
                    spaceAccess: spaceAccess,
                    capabilities: capabilities,
                    promotionNamespace: promotionNamespace,
                    pullNewIcon: pullNewIcon,
                    restoreSavedLocation: restoreSavedLocation,
                    select: select,
                    isExpanded: expansionBinding(for: node.id),
                    editingFolderRequest: $editingFolderRequest
                )
                .crestCollectionItemTransition()
            }

            if capabilities.showsRowDropIndicators {
                VStack(spacing: 0) { rows }

                // Also the band an empty unfiled run draws its insertion line
                // in: it sits directly below the folder groups, where that
                // run's first row would appear.
                BrowserSavedTabsEndDropTarget(
                    tabs: tabSections.unfiledSavedTabs,
                    browser: browser,
                    capabilities: capabilities
                )
                .browserSidebarReorderSectionIndicator(
                    section,
                    state: browser.sidebarReorderState
                )
            } else {
                VStack(spacing: 0) {
                    rows

                    // A Space whose every saved tab lives in a folder still has
                    // an unfiled run. Without a band of its own that run has no
                    // region to aim at, nowhere to draw its insertion line, and
                    // no way to take a tab that belongs outside the folders.
                    if unfiledItems.isEmpty {
                        Color.clear
                            .frame(height: metrics.sectionEndBandHeight)
                            .contentShape(.rect)
                            .accessibilityHidden(true)
                    }
                }
                .browserSidebarReorderSectionIndicator(
                    section,
                    state: browser.sidebarReorderState
                )
            }
        }
        .crestCollectionMotion(ids: collectionMotionIDs)
        .contentShape(.rect)
        .browserSidebarReorderZone(
            .section(section),
            state: browser.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .section(.folders(parentID: nil)),
            state: browser.sidebarReorderState
        )
        .modifier(
            BrowserSidebarSectionReservation(
                section: section,
                state: browser.sidebarReorderState,
                capabilities: capabilities
            )
        )
        .accessibilityHint("Drop a tab here to save it")
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(unfiledItems) { item in
            switch item {
            case .tab(let tab):
                let followingTabID = followingTabIDs[tab.id]
                BrowserSidebarTabRow(
                    tab: tab,
                    spaceID: space.id,
                    profileID: space.profile.id,
                    isSelected: tab.id == space.selectedTabID,
                    canClose: false,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    capabilities: capabilities,
                    isLoaded: pageAccess.containsResidentPage(tab.id),
                    unload: { pageAccess.unloadPage($0, assignment) },
                    pullNewIcon: { pullNewIcon(tab.id) },
                    restoreSavedLocation: { restoreSavedLocation(tab.id) },
                    promotionNamespace: promotionNamespace,
                    followingTabID: followingTabID,
                    hasVisibleFollowingRow: followingTabID != nil,
                    select: select
                )
                .id(tab.id)
            case .splitGroup(let groupID, let members):
                let followingTabID = members.last.flatMap {
                    followingTabIDs[$0.id]
                }
                BrowserSidebarSplitGroupRow(
                    groupID: groupID,
                    members: members,
                    spaceID: space.id,
                    profileID: space.profile.id,
                    selectedTabID: space.selectedTabID,
                    canClose: false,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    capabilities: capabilities,
                    isLoaded: pageAccess.containsResidentPage,
                    unload: { pageAccess.unloadPage($0, assignment) },
                    pullNewIcon: pullNewIcon,
                    restoreSavedLocation: restoreSavedLocation,
                    promotionNamespace: promotionNamespace,
                    followingTabID: followingTabID,
                    hasVisibleFollowingRow: followingTabID != nil,
                    select: select
                )
            }
        }
    }

    private var folderNodes: [BrowserFolderNode] {
        space.folderTree.flattenedNodes(
            collapsedFolderIDs: Set(
                space.folders.lazy.filter(\.isCollapsed).map(\.id)
            )
        )
    }

    private var unfiledItems: [BrowserSidebarTabListItem] {
        BrowserSidebarTabListItemPolicy.items(for: tabSections.unfiledSavedTabs)
    }

    /// The row each unfiled row would insert in front of, which only a shell
    /// that draws its insertion line on the rows themselves reads.
    private var followingTabIDs: [TabID: TabID] {
        guard capabilities.showsRowDropIndicators else { return [:] }
        return BrowserTabRowInsertionPolicy.followingTabIDs(
            in: tabSections.unfiledSavedTabs
        )
    }

    private var collectionMotionIDs: [String] {
        folderNodes.map { "folder-\($0.id.rawValue.uuidString)" }
            + space.tabs
            .filter { $0.placement == .saved && $0.folderID != nil }
            .map { "tab-\($0.id.rawValue.uuidString)" }
            + unfiledItems.map(\.collectionMotionID)
    }

    private var metrics: BrowserSidebarTabListMetrics {
        BrowserSidebarInteractionPolicy.tabListMetrics(capabilities)
    }

    private func pullNewIcon(_ tabID: TabID) {
        let actions = tabActions
        Task {
            await actions.pullNewIcon(for: tabID)
        }
    }

    private func expansionBinding(for folderID: FolderID) -> Binding<Bool> {
        Binding {
            !(browser.session.space(id: space.id)?.folders.first(where: {
                $0.id == folderID
            })?.isCollapsed ?? false)
        } set: { isExpanded in
            guard isCurrentAndUnlocked else { return }
            browser.setFolderCollapsed(
                folderID,
                matching: assignment,
                isCollapsed: !isExpanded
            )
        }
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    private var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }
}
