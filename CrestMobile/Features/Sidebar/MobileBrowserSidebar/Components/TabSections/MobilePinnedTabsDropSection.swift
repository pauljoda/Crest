import SwiftUI
import UniformTypeIdentifiers

struct MobilePinnedTabsDropSection: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (TabID) -> Void
    let tabPromotionNamespace: Namespace.ID
    let usesNativeNavigationTransition: Bool

    @State private var isDropTargeted = false

    private var dropLocation: BrowserTabDropLocation {
        .init(placement: .pinned, folderID: nil, beforeTabID: nil)
    }

    var body: some View {
        Group {
            if tabSections.pinnedTabs.isEmpty {
                Color.clear
                    .frame(height: MobileSidebarDropTargetPolicy.sectionEndTargetHeight)
                    .contentShape(.rect)
                    .accessibilityHidden(true)
            } else {
                PinnedTabGrid(
                    tabs: tabSections.pinnedTabs,
                    assignment: assignment,
                    selectedTabID: space.selectedTabID,
                    select: { runtimeAssignment in
                        guard isCurrentAndUnlocked else { return }
                        selectTab(runtimeAssignment.tabID)
                    },
                    moveTab: move,
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
                    pullNewIcon: { pullNewIcon($0.tabID) },
                    restoreSavedLocation: { restoreSavedLocation($0.tabID) },
                    siteThemeAccent: pages.siteThemeIconAccent(matching:),
                    promotionNamespace: tabPromotionNamespace,
                    usesNativeNavigationTransition: usesNativeNavigationTransition
                )
            }
        }
        .contentShape(.rect)
        .browserSidebarReorderSectionIndicator(
            .tabs(placement: .pinned, folderID: nil),
            state: browser.sidebarReorderState
        )
        // On the whole section, not just the empty placeholder: a zone inside
        // one branch vanishes the moment any tab is pinned, and dragging into a
        // populated grid becomes impossible.
        .browserSidebarReorderZone(
            .section(.tabs(placement: .pinned, folderID: nil)),
            state: browser.sidebarReorderState
        )
        .accessibilityHint("Drop a tab here to pin it")
    }

    private func move(_ item: BrowserTabDragItem, before tabID: TabID?) -> Bool {
        guard isCurrentAndUnlocked else { return false }
        return BrowserTabDragAction(
            browser: browser,
            spaceAccess: spaceAccess
        ).move(
            item,
            to: .pinned,
            before: tabID,
            matching: assignment
        )
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
