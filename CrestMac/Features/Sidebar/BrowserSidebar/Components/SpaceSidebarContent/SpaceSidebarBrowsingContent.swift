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
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    @Binding var isSavedTabsExpanded: Bool
    let toggleSavedTabs: () -> Void
    let openNewTab: () -> Void
    let beginCreatingFolder: () -> Void
    let showHistory: () -> Void
    let tabPromotionNamespace: Namespace.ID
    let editSpace: () -> Void
    let createSpace: (() -> Void)?

    /// The clear-current-tabs control appears while a pointer rests anywhere
    /// over the list, so the state belongs to the whole scrolling region rather
    /// than to the seam that draws it.
    @State private var isHoveringTabList = false

    var body: some View {
        if let listContext {
            content(listContext)
        }
    }

    @ViewBuilder
    private func content(_ listContext: BrowserSidebarListContext) -> some View {
        let hasPinnedTabs = !listContext.space.sidebar.section(.pinned).isEmpty
        BrowserPinnedTabsDropSection(context: listContext)
            .equatable()
            .padding(.horizontal, CrestSpacing.small)
            // The native Space host clips at this section's top edge. Keep the
            // glow's drawing margin inside it, including below extension toolbars.
            .padding(.top, hasPinnedTabs ? BrowserTabSelectionGlow.outset : 0)
            .padding(.bottom, hasPinnedTabs ? BrowserSidebarMetrics.pinnedTabsBottomInset : 0)

        BrowserSpaceHeader(
            space: space,
            isPrivateBrowsing: browser.isPrivateBrowsing,
            isSavedTabsExpanded: $isSavedTabsExpanded,
            capabilities: capabilities,
            actions: BrowserSpaceHeaderActions(
                openNewTab: openNewTab,
                createFolder: beginCreatingFolder,
                showHistory: showHistory,
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
                context: listContext,
                showsClearAction: isHoveringTabList,
                openNewTab: openNewTab
            )
            .equatable()
        }
        .onHover { isHoveringTabList = $0 }
        .background {
            BrowserSidebarSelectionReconciler(
                context: listContext, interaction: sidebarInteraction)
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

    /// The Space and this window as the read model keeps them, and what the
    /// rows act through.
    private var listContext: BrowserSidebarListContext? {
        guard let spaceModel = browser.spaceModel(space.id), let window = browser.windowModel else { return nil }
        return BrowserSidebarListContext(
            space: spaceModel, window: window, favicons: browser.core.state.favicons, browser: browser,
            spaceAccess: spaceAccess, pageAccess: pageAccess, tabActions: tabActions, capabilities: capabilities,
            promotionNamespaces: [.current: tabPromotionNamespace], select: activate,
            restoreSavedLocation: restoreSavedLocation)
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
            units: BrowserSidebarSelection.itemUnits(in: browser))
        BrowserTabActivationPolicy.activate(
            tabID,
            selectTab: browser.selectTab,
            presentPage: { pages.select(session: browser.presented) }
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
}

/// Model and residency changes reconcile selection and the rows collapsed
/// folders keep, even when folder rows are not mounted. This leaf keeps that
/// observation out of the scrolling row hierarchy.
private struct BrowserSidebarSelectionReconciler: View {
    let context: BrowserSidebarListContext
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
        let browser = context.browser
        interaction.sidebarSpaceAccess = context.spaceAccess
        if let workspace = browser.workspaceModel {
            interaction.pruneCollapsedFolders(
                keepingFoldersOf: workspace.spaces.models.filter { !context.spaceAccess.isLocked($0) })
        }
        let space = context.space
        guard browser.spaceModel(space.id) === space, !context.spaceAccess.isLocked(space) else { return }
        for folder in space.folders.models {
            let folderTabIDs = space.sidebar.inside(folder.id).rows.filter { !$0.kind.opensList }.flatMap(\.members)
            interaction.reconcileCollapsedFolder(
                BrowserFolderRuntimeAssignment(folderID: folder.id, spaceID: space.id, profileID: space.profileID),
                isExpanded: !folder.isCollapsed,
                selectedTabID: folderTabIDs.first { context.window.shownTabIDs.contains($0) },
                folderTabIDs: folderTabIDs,
                residentFolderTabIDs: folderTabIDs.filter {
                    context.pageAccess.containsResidentPageMatching(
                        BrowserTabRuntimeAssignment(tabID: $0, spaceID: space.id, profileID: space.profileID))
                })
        }
        guard browser.selectedSpaceID == space.id,
            !interaction.sidebarReorderState.hasLiftInFlight
        else { return }
        browser.tabMultiSelection.reconcile(
            units: BrowserSidebarSelection.itemUnits(in: browser))
    }

    /// What reconciling reads, observed here rather than by any row: the
    /// Space's lists and folders, which of its tabs the window shows, whether
    /// it is shown and unlocked, and residency.
    private var snapshot: Snapshot {
        let space = context.space
        let lists = space.sidebar.lists.map(\.rows)
        let listed = lists.flatMap { $0.flatMap(\.members) }
        return Snapshot(
            lists: lists,
            folders: space.folders.models.map { Snapshot.Folder(id: $0.id, isCollapsed: $0.isCollapsed) },
            shownTabIDs: listed.filter { context.window.shownTabIDs.contains($0) },
            isSavedTabsExpanded: space.settings.isSavedTabsExpanded,
            isSelected: context.window.shownSpaceID == space.id,
            isUnlocked: !context.spaceAccess.isLocked(space),
            residencyRevision: context.pageAccess.residencyRevision(),
            spaceIDs: context.browser.workspaceModel?.spaces.models.map(\.id) ?? [])
    }

    private struct Snapshot: Equatable {
        struct Folder: Equatable {
            let id: FolderID
            let isCollapsed: Bool
        }
        let lists: [[SidebarRow]]
        let folders: [Folder]
        let shownTabIDs: [TabID]
        let isSavedTabsExpanded: Bool
        let isSelected: Bool
        let isUnlocked: Bool
        let residencyRevision: Int
        /// Evicted Space hosts still need their retained visibility pruned when
        /// Spaces disappear or access is revoked.
        let spaceIDs: [SpaceID]
    }
}
