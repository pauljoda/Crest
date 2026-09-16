import SwiftUI

/// One Space's moving sidebar content: the pinned grid, the Space header, and
/// the scrolling tab list. Address and navigation controls stay outside it.
///
/// Everything here is composition and binding. The sections and the list are the
/// shared ones; this shell supplies scrolling chrome and the page-facing
/// closures that need the windowed card pool.
struct SpaceSidebarBrowsingContent: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    @Binding var isSavedTabsExpanded: Bool
    let toggleSavedTabs: () -> Void
    let openNewTab: () -> Void
    let beginCreatingFolder: () -> Void
    let showHistory: () -> Void
    let showExtensions: () -> Void
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?
    let tabPromotionNamespace: Namespace.ID
    let editSpace: () -> Void
    let createSpace: (() -> Void)?

    /// The clear-current-tabs control appears while a pointer rests anywhere
    /// over the list, so the state belongs to the whole scrolling region rather
    /// than to the seam that draws it.
    @State private var isHoveringTabList = false

    var body: some View {
        BrowserPinnedTabsDropSection(
            space: space,
            tabSections: tabSections,
            browser: browser,
            spaceAccess: spaceAccess,
            pageAccess: pageAccess,
            tabActions: tabActions,
            capabilities: capabilities,
            restoreSavedLocation: restoreSavedLocation,
            select: activate
        )
        .padding(.horizontal, CrestSpacing.small)
        // The native Space host clips at this section's top edge. Keep the
        // glow's drawing margin inside it, including below extension toolbars.
        .padding(.top, tabSections.pinnedTabs.isEmpty ? 0 : BrowserTabSelectionGlow.outset)
        .padding(.bottom, pinnedTabsBottomInset)

        BrowserSpaceHeader(
            space: space,
            isPrivateBrowsing: browser.isPrivateBrowsing,
            isSavedTabsExpanded: $isSavedTabsExpanded,
            capabilities: capabilities,
            actions: BrowserSpaceHeaderActions(
                openNewTab: openNewTab,
                createFolder: beginCreatingFolder,
                showHistory: showHistory,
                showExtensions: showExtensions,
                cleanup: browser.cleanupCurrentTabs,
                toggleSavedTabs: toggleSavedTabs
            )
        )

        SpaceSidebarTabListScroll(browser: browser) {
            BrowserSidebarBackgroundInteractionView(
                editSpace: editSpace,
                createSpace: createSpace
            )
            .modifier(
                BrowserSidebarEmptySpaceNewTabGesture(
                    tabActions: tabActions,
                    openNewTab: openNewTab
                )
            )
        } content: {
            BrowserSidebarTabList(
                space: space,
                tabSections: tabSections,
                browser: browser,
                spaceAccess: spaceAccess,
                pageAccess: pageAccess,
                tabActions: tabActions,
                capabilities: capabilities,
                isSavedTabsExpanded: isSavedTabsExpanded,
                promotionNamespace: tabPromotionNamespace,
                showsClearAction: isHoveringTabList,
                restoreSavedLocation: restoreSavedLocation,
                select: activate,
                openNewTab: openNewTab,
                editingFolderRequest: $editingFolderRequest
            )
        }
        .onHover { isHoveringTabList = $0 }
        .background {
            BrowserSidebarSelectionReconciler(
                assignment: BrowserSpaceRuntimeAssignment(space: space), browser: browser,
                pageAccess: pageAccess, spaceAccess: spaceAccess, interaction: sidebarInteraction)
        }
        .background {
            BrowserTabSelectionMonitor(
                browser: browser, spaceAccess: spaceAccess,
                assignment: BrowserSpaceRuntimeAssignment(space: space), activate: activate,
                ownsFocus: browser.tabMultiSelection.isEngaged && browser.tabMultiSelection.ownsKeyboardFocus)
        }
        .alert(
            "Tab Selection",
            isPresented: Binding(
                get: { browser.tabMultiSelection.message != nil },
                set: { if !$0 { browser.tabMultiSelection.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { browser.tabMultiSelection.message = nil }
        } message: {
            Text(browser.tabMultiSelection.message ?? "")
        }
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser, spaceAccess: spaceAccess)
    }

    private var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            browser: browser, reorderState: sidebarInteraction.sidebarReorderState,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    /// Selection and presentation in the one order that works: the page a
    /// shell brings on screen is whichever one the session now points at.
    private func activate(_ tabID: TabID) {
        browser.tabMultiSelection.click(
            tabID,
            units: BrowserSidebarSelection.itemUnits(in: browser, reorder: sidebarInteraction.sidebarReorderState))
        BrowserTabActivationPolicy.activate(
            tabID,
            selectTab: browser.selectTab,
            presentPage: { pages.select(session: browser.session) }
        )
    }

    private func restoreSavedLocation(_ tabID: TabID) {
        BrowserSavedLocationRestoreAction(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        ).perform(
            BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
    }

    private var pinnedTabsBottomInset: CGFloat {
        tabSections.pinnedTabs.isEmpty
            ? 0
            : BrowserSidebarMetrics.pinnedTabsBottomInset
    }
}

/// Model and residency changes reconcile selection even when folder rows are
/// not mounted. This leaf keeps observation out of the scrolling row hierarchy.
private struct BrowserSidebarSelectionReconciler: View {
    let assignment: BrowserSpaceRuntimeAssignment
    let browser: BrowserStore
    let pageAccess: BrowserSidebarPageAccess
    let spaceAccess: BrowserSpaceAccessController
    let interaction: BrowserSidebarInteractionState

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: snapshot, initial: true) { _, _ in reconcile() }
            .onChange(of: interaction.sidebarReorderState.hasLiftInFlight) { _, isDragging in
                if !isDragging { reconcile() }
            }
    }

    private func reconcile() {
        interaction.sidebarSpaceAccess = spaceAccess
        interaction.pruneCollapsedFolders(in: browser.session.spaces.filter { !spaceAccess.isLocked($0) })
        guard let space = browser.space(matching: assignment), !spaceAccess.isLocked(space) else { return }
        let resident = Set(
            space.tabs.compactMap { tab in
                pageAccess.containsResidentPageMatching(
                    BrowserTabRuntimeAssignment(
                        tabID: tab.id, spaceID: assignment.spaceID, profileID: assignment.profileID)) ? tab.id : nil
            })
        interaction.reconcileCollapsedFolders(in: space, residentTabIDs: resident)
        guard browser.session.selectedSpaceID == assignment.spaceID,
            !interaction.sidebarReorderState.hasLiftInFlight
        else { return }
        browser.tabMultiSelection.reconcile(
            units: BrowserSidebarSelection.itemUnits(
                in: browser, reorder: interaction.sidebarReorderState))
    }

    private var snapshot: Snapshot {
        let space = browser.space(matching: assignment)
        return Snapshot(
            tabs: space?.tabs.map {
                Snapshot.Tab(
                    id: $0.id, placement: $0.placement, folderID: $0.folderID,
                    splitGroupID: $0.splitGroupID, isStartPage: $0.isStartPage)
            } ?? [],
            folders: space?.folders ?? [], selectedTabID: space?.selectedTabID,
            isSavedTabsExpanded: space?.isSavedTabsExpanded ?? false,
            isSelected: browser.session.selectedSpaceID == assignment.spaceID,
            isUnlocked: space.map { !spaceAccess.isLocked($0) } ?? false,
            residencyRevision: pageAccess.residencyRevision(),
            spaceMembership: browser.session.spaces.map {
                Snapshot.SpaceMembership(
                    assignment: BrowserSpaceRuntimeAssignment(space: $0),
                    folderIDs: $0.folders.map(\.id), isUnlocked: !spaceAccess.isLocked($0))
            })
    }

    private struct Snapshot: Equatable {
        struct Tab: Equatable {
            let id: TabID
            let placement: TabPlacement
            let folderID: FolderID?
            let splitGroupID: SplitGroupID?
            let isStartPage: Bool
        }
        /// Evicted Space hosts still need their retained visibility pruned when
        /// folders disappear, assignments change, or access is revoked.
        struct SpaceMembership: Equatable {
            let assignment: BrowserSpaceRuntimeAssignment
            let folderIDs: [FolderID]
            let isUnlocked: Bool
        }
        let tabs: [Tab]
        let folders: [BrowserFolder]
        let selectedTabID: TabID?
        let isSavedTabsExpanded: Bool
        let isSelected: Bool
        let isUnlocked: Bool
        let residencyRevision: Int
        let spaceMembership: [SpaceMembership]
    }
}
