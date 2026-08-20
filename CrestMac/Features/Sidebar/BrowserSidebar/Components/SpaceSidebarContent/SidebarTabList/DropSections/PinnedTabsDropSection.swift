import SwiftUI
import UniformTypeIdentifiers

struct PinnedTabsDropSection: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

    private var dropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .pinned,
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
        Group {
            if tabSections.pinnedTabs.isEmpty {
                Color.clear
                    .frame(height: BrowserSidebarMetrics.pinnedEmptyDropHeight)
            } else {
                PinnedTabGrid(
                    tabs: tabSections.pinnedTabs,
                    assignment: assignment,
                    selectedTabID: space.selectedTabID,
                    select: { runtimeAssignment in
                        guard isCurrentAndUnlocked else { return }
                        browser.selectTab(runtimeAssignment.tabID)
                        pages.select(session: browser.session)
                    },
                    moveTab: { item, destinationTabID in
                        guard isCurrentAndUnlocked else { return false }
                        return BrowserTabDragAction(
                            browser: browser,
                            spaceAccess: spaceAccess
                        ).move(
                            item,
                            to: .pinned,
                            before: destinationTabID,
                            matching: assignment
                        )
                    },
                    dragState: browser.tabDragState,
                    browser: browser,
                    spaceAccess: spaceAccess,
                    isLoaded: pages.containsResidentPage(matching:),
                    unload: { runtimeAssignment in
                        pages.unloadPage(
                            for: runtimeAssignment.tabID,
                            matching: assignment
                        )
                    },
                    pullNewIcon: { runtimeAssignment in
                        pullNewIcon(runtimeAssignment.tabID)
                    },
                    restoreSavedLocation: { runtimeAssignment in
                        BrowserSavedLocationRestoreAction(
                            browser: browser,
                            pages: pages,
                            spaceAccess: spaceAccess
                        ).perform(runtimeAssignment)
                    },
                    siteThemeAccent: pages.siteThemeIconAccent(matching:)
                )
            }
        }
        .contentShape(.rect)
        .browserSidebarReorderSectionIndicator(
            .tabs(placement: .pinned, folderID: nil),
            state: browser.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .section(.tabs(placement: .pinned, folderID: nil)),
            state: browser.sidebarReorderState
        )
        .accessibilityHint("Drop a tab here to pin it")
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

    private var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }
}
