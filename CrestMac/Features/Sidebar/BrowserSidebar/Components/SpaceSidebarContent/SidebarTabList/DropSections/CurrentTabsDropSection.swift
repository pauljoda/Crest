import SwiftUI
import UniformTypeIdentifiers

struct CurrentTabsDropSection: View {
    let space: BrowserSpace
    let tabs: [BrowserTab]
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let openNewTab: () -> Void
    let tabPromotionNamespace: Namespace.ID

    private var dropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: nil
        )
    }

    private var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    var body: some View {
        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)

        VStack(spacing: 0) {
            NewTabRow(action: openNewTab)

            // The current tabs are a run of their own inside this section's
            // zone: they start below the new-tab row, which is where a cleared
            // list has to show that it will still take a drop.
            VStack(spacing: 0) {
                ForEach(items) { item in
                    switch item {
                    case .tab(let tab):
                        BrowserSidebarTabRow(
                            tab: tab,
                            spaceID: space.id,
                            profileID: space.profile.id,
                            isSelected: tab.id == space.selectedTabID,
                            canClose: true,
                            browser: browser,
                            spaceAccess: spaceAccess,
                            capabilities: capabilities,
                            isLoaded: pages.containsResidentPage(for: tab.id),
                            unload: { tabID in
                                pages.unloadPage(for: tabID, matching: assignment)
                            },
                            pullNewIcon: { tabActions.pullNewIcon(for: tab.id) },
                            promotionNamespace: tabPromotionNamespace,
                            select: activate
                        )
                    case .splitGroup(let groupID, let members):
                        SidebarSplitGroupRow(
                            groupID: groupID,
                            members: members,
                            spaceID: space.id,
                            profileID: space.profile.id,
                            selectedTabID: space.selectedTabID,
                            canClose: true,
                            browser: browser,
                            spaceAccess: spaceAccess,
                            presentSelectedPage: {
                                pages.select(session: browser.session)
                            },
                            isLoaded: { pages.containsResidentPage(for: $0) },
                            unload: { tabID in
                                pages.unloadPage(for: tabID, matching: assignment)
                            },
                            pullNewIcon: { tabID in
                                tabActions.pullNewIcon(for: tabID)
                            }
                        )
                    }
                }

                // A cleared list has no row to draw the seam on, so it keeps a
                // band under the new-tab row for the line to stand in.
                if items.isEmpty {
                    Color.clear
                        .frame(height: CrestSpacing.medium)
                }
            }
            .browserSidebarReorderSectionIndicator(
                .tabs(placement: .current, folderID: nil),
                state: browser.sidebarReorderState
            )
        }
        .crestCollectionMotion(ids: items.map(\.id))
        .contentShape(.rect)
        .browserSidebarReorderZone(
            .section(.tabs(placement: .current, folderID: nil)),
            state: browser.sidebarReorderState
        )
        .accessibilityHint("Drop a tab here to make it a current tab")
    }

    /// Selection and presentation in the one order that works: the page a
    /// shell brings on screen is whichever one the session now points at.
    private func activate(_ tabID: TabID) {
        BrowserTabActivationPolicy.activate(
            tabID,
            selectTab: browser.selectTab,
            presentPage: { pages.select(session: browser.session) }
        )
    }

    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
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
