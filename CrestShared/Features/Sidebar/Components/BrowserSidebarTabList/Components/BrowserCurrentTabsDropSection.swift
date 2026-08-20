import SwiftUI

/// The Space's current tabs as one drop section, on every shell: the new-tab row
/// and the run of rows below it.
///
/// The current tabs are a run of their own inside this section's zone. They
/// start below the new-tab row, which is where a cleared list has to show that
/// it will still take a drop.
struct BrowserCurrentTabsDropSection: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let pageAccess: BrowserSidebarPageAccess
    let tabActions: BrowserSidebarTabActions
    let capabilities: BrowserInteractionCapabilities
    var promotionNamespace: Namespace.ID? = nil
    /// What opening a tab means to the host. The rows decide *whether*; the host
    /// decides what appears.
    let select: (TabID) -> Void
    let openNewTab: () -> Void

    private var tabs: [BrowserTab] { tabSections.sidebarCurrentTabs }

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: .current, folderID: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserNewTabRow(capabilities: capabilities, action: openNewTab)

            if capabilities.showsRowDropIndicators {
                VStack(spacing: 0) { rows }

                // Also the band a cleared list draws its insertion line in: it
                // sits directly below the new-tab row, where the first current
                // tab would appear.
                BrowserCurrentTabsEndDropTarget(
                    tabs: tabs,
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

                    // A cleared list has no row to draw the seam on, so it
                    // keeps a band under the new-tab row for the line to stand
                    // in.
                    if items.isEmpty {
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
        .crestCollectionMotion(ids: items.map(\.id))
        .contentShape(.rect)
        .browserSidebarReorderZone(
            .section(section),
            state: browser.sidebarReorderState
        )
        .modifier(
            BrowserSidebarSectionReservation(
                section: section,
                state: browser.sidebarReorderState,
                capabilities: capabilities
            )
        )
        .accessibilityHint("Drop a tab here to make it a current tab")
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(items) { item in
            switch item {
            case .tab(let tab):
                let followingTabID = followingTabIDs[tab.id]
                BrowserSidebarTabRow(
                    tab: tab,
                    spaceID: space.id,
                    profileID: space.profile.id,
                    isSelected: tab.id == space.selectedTabID,
                    canClose: true,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    capabilities: capabilities,
                    isLoaded: pageAccess.containsResidentPage(tab.id),
                    unload: { pageAccess.unloadPage($0, assignment) },
                    pullNewIcon: { pullNewIcon(tab.id) },
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
                    canClose: true,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    capabilities: capabilities,
                    isLoaded: pageAccess.containsResidentPage,
                    unload: { pageAccess.unloadPage($0, assignment) },
                    pullNewIcon: pullNewIcon,
                    promotionNamespace: promotionNamespace,
                    followingTabID: followingTabID,
                    hasVisibleFollowingRow: followingTabID != nil,
                    select: select
                )
            }
        }
    }

    private var items: [BrowserSidebarTabListItem] {
        BrowserSidebarTabListItemPolicy.items(for: tabs)
    }

    /// The row each row would insert in front of, which only a shell that draws
    /// its insertion line on the rows themselves reads. Everywhere else the
    /// section's own zone carries the whole answer, and building the map would
    /// be work nothing looks at.
    private var followingTabIDs: [TabID: TabID] {
        guard capabilities.showsRowDropIndicators else { return [:] }
        return BrowserTabRowInsertionPolicy.followingTabIDs(in: tabs)
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

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }
}
