import SwiftUI
import UniformTypeIdentifiers

struct SavedTabsDropSection: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?

    private var dropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .saved,
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
        let folderTree = space.folderTree
        let collapsedFolderIDs = Set(
            space.folders.lazy.filter(\.isCollapsed).map(\.id)
        )
        let folderNodes = folderTree.flattenedNodes(
            collapsedFolderIDs: collapsedFolderIDs
        )
        let unfiledItems = BrowserSidebarTabListItemPolicy.items(
            for: tabSections.unfiledSavedTabs
        )
        let folderRowIDs = folderNodes.map {
            "folder-\($0.id.rawValue.uuidString)"
        }
        let nestedTabRowIDs = space.tabs
            .filter { $0.placement == .saved && $0.folderID != nil }
            .map { "tab-\($0.id.rawValue.uuidString)" }
        let unfiledRowIDs = unfiledItems.map(\.collectionMotionID)

        VStack(spacing: 0) {
            ForEach(folderNodes) { node in
                SavedFolderGroup(
                    node: node,
                    tabs: tabSections.savedTabs(in: node.id),
                    spaceID: space.id,
                    profileID: space.profile.id,
                    selectedTabID: space.selectedTabID,
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    isExpanded: expansionBinding(for: node.id),
                    editingFolderRequest: $editingFolderRequest
                )
                .crestCollectionItemTransition()
            }

            // The saved tabs that are in no folder, kept as a run of their own
            // so the drop feedback for that run has somewhere to appear. The
            // folder groups above share this section's zone, and the unfiled
            // rows land below them.
            VStack(spacing: 0) {
                ForEach(unfiledItems) { item in
                    switch item {
                    case .tab(let tab):
                        SidebarTabRow(
                            tab: tab,
                            spaceID: space.id,
                            profileID: space.profile.id,
                            isSelected: tab.id == space.selectedTabID,
                            canClose: false,
                            browser: browser,
                            spaceAccess: spaceAccess,
                            presentSelectedPage: {
                                pages.select(session: browser.session)
                            },
                            isLoaded: pages.containsResidentPage(for: tab.id),
                            unload: { tabID in
                                pages.unloadPage(for: tabID, matching: assignment)
                            },
                            pullNewIcon: { tabActions.pullNewIcon(for: tab.id) },
                            restoreSavedLocation: {
                                tabActions.restoreSavedLocation(for: tab.id)
                            }
                        )
                    case .splitGroup(let groupID, let members):
                        SidebarSplitGroupRow(
                            groupID: groupID,
                            members: members,
                            spaceID: space.id,
                            profileID: space.profile.id,
                            selectedTabID: space.selectedTabID,
                            canClose: false,
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
                            },
                            restoreSavedLocation: { tabID in
                                tabActions.restoreSavedLocation(for: tabID)
                            }
                        )
                    }
                }

                // A Space whose every saved tab lives in a folder still has an
                // unfiled run. Without a band of its own that run has no region
                // to aim at, nowhere to draw its insertion line, and no way to
                // take a tab that belongs outside the folders.
                if unfiledItems.isEmpty {
                    Color.clear
                        .frame(height: CrestSpacing.medium)
                }
            }
            .browserSidebarReorderSectionIndicator(
                .tabs(placement: .saved, folderID: nil),
                state: browser.sidebarReorderState
            )
        }
        .crestCollectionMotion(
            ids: folderRowIDs + nestedTabRowIDs + unfiledRowIDs
        )
        .contentShape(.rect)
        .browserSidebarReorderZone(
            .section(.tabs(placement: .saved, folderID: nil)),
            state: browser.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .section(.folders(parentID: nil)),
            state: browser.sidebarReorderState
        )
        .accessibilityHint("Drop a tab here to save it")
    }

    private func expansionBinding(for folderID: FolderID) -> Binding<Bool> {
        Binding(
            get: {
                !(browser.session.space(id: space.id)?.folders.first(where: {
                    $0.id == folderID
                })?.isCollapsed ?? false)
            },
            set: { isExpanded in
                guard isCurrentAndUnlocked else { return }
                browser.setFolderCollapsed(
                    folderID,
                    matching: assignment,
                    isCollapsed: !isExpanded
                )
            }
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
