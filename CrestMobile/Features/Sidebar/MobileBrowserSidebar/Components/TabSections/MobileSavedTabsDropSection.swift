import SwiftUI

struct MobileSavedTabsDropSection: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (TabID) -> Void
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?
    let tabPromotionNamespace: Namespace.ID
    let usesNativeNavigationTransition: Bool

    @State private var isDropTargeted = false

    var body: some View {
        let collapsedFolderIDs = Set(
            space.folders.lazy.filter(\.isCollapsed).map(\.id)
        )
        let folderNodes = space.folderTree.flattenedNodes(
            collapsedFolderIDs: collapsedFolderIDs
        )
        let followingTabIDs = BrowserTabRowInsertionPolicy.followingTabIDs(
            in: tabSections.unfiledSavedTabs
        )
        let unfiledItems = BrowserSidebarTabListItemPolicy.items(
            for: tabSections.unfiledSavedTabs
        )

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
                    promotionNamespace: tabPromotionNamespace,
                    pullNewIcon: pullNewIcon,
                    restoreSavedLocation: restoreSavedLocation,
                    select: selectTab,
                    isExpanded: expansionBinding(for: node.id),
                    editingFolderRequest: $editingFolderRequest
                )
                .crestCollectionItemTransition()
            }

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
                        isLoaded: pages.containsResidentPage(for: tab.id),
                        unload: { tabID in
                            pages.unloadPage(for: tabID, matching: assignment)
                        },
                        pullNewIcon: { pullNewIcon(tab.id) },
                        restoreSavedLocation: { restoreSavedLocation(tab.id) },
                        promotionNamespace: tabPromotionNamespace,
                        followingTabID: followingTabID,
                        hasVisibleFollowingRow: followingTabID != nil,
                        select: selectTab
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
                        isLoaded: { pages.containsResidentPage(for: $0) },
                        unload: { tabID in
                            pages.unloadPage(for: tabID, matching: assignment)
                        },
                        pullNewIcon: pullNewIcon,
                        restoreSavedLocation: restoreSavedLocation,
                        promotionNamespace: tabPromotionNamespace,
                        followingTabID: followingTabID,
                        hasVisibleFollowingRow: followingTabID != nil,
                        select: selectTab
                    )
                }
            }

            // Also the band an empty unfiled run draws its insertion line in:
            // it sits directly below the folder groups, where that run's first
            // row would appear.
            MobileSavedTabsEndDropTarget(
                tabs: tabSections.unfiledSavedTabs,
                browser: browser,
                isTargeted: $isDropTargeted,
                moveTab: move,
                moveFolder: moveFolder
            )
            .browserSidebarReorderSectionIndicator(
                .tabs(placement: .saved, folderID: nil),
                state: browser.sidebarReorderState
            )
        }
        .crestCollectionMotion(
            ids: folderNodes.map { "folder-\($0.id.rawValue.uuidString)" }
                + space.tabs
                .filter { $0.placement == .saved && $0.folderID != nil }
                .map { "tab-\($0.id.rawValue.uuidString)" }
                + unfiledItems.map(\.collectionMotionID)
        )
        .browserSidebarReorderZone(
            .section(.tabs(placement: .saved, folderID: nil)),
            state: browser.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .section(.folders(parentID: nil)),
            state: browser.sidebarReorderState
        )
        .browserSidebarReorderSectionReservation(
            .tabs(placement: .saved, folderID: nil),
            state: browser.sidebarReorderState
        )
    }

    private func moveFolder(
        _ item: BrowserFolderDragItem,
        to location: BrowserFolderDropLocation
    ) -> Bool {
        guard isCurrentAndUnlocked else { return false }
        return browser.moveFolder(
            item,
            matching: assignment,
            into: location.parentID,
            before: location.beforeSiblingID
        )
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

    private func move(_ item: BrowserTabDragItem, before tabID: TabID?) -> Bool {
        guard isCurrentAndUnlocked else { return false }
        return BrowserTabDragAction(
            browser: browser,
            spaceAccess: spaceAccess
        ).move(
            item,
            to: .saved,
            before: tabID,
            matching: assignment
        )
    }

    /// What this shell can do, until the shell itself hands it down: a finger
    /// is the primary input, a trackpad may still be attached, and the section
    /// draws its drop feedback on the rows.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(
            supportsHover: true,
            supportsTouch: true,
            showsRowDropIndicators: true,
            reservesReorderSectionZones: true,
            usesNativeNavigationTransition: usesNativeNavigationTransition
        )
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser)
    }

    private func pullNewIcon(_ tabID: TabID) {
        let actions = BrowserSidebarTabActions(
            assignment: assignment,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
        Task {
            await actions.pullNewIcon(for: tabID)
        }
    }

    private func restoreSavedLocation(_ tabID: TabID) {
        guard isCurrentAndUnlocked else { return }
        MobileSavedLocationRestoreAction(
            browser: browser,
            pages: pages,
            selectTab: selectTab
        ).perform(
            BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
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
