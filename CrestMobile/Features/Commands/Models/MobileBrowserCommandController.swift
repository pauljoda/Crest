import SwiftUI

@MainActor
struct MobileBrowserCommandController {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore

    var orderedTabs: [BrowserTab] {
        browser.selectedSpace?.tabs ?? []
    }

    var canArchiveSelectedTab: Bool {
        browser.selectedTab?.placement == .current
            && browser.selectedTab?.isStartPage == false
    }

    var canDismissSelectedTab: Bool {
        BrowserTabDismissalPolicy.action(
            for: browser.selectedTab,
            tabCount: orderedTabs.count
        ) != .closeWindow
    }

    var canDuplicateSelectedTab: Bool {
        browser.selectedTab?.isStartPage == false
    }

    var canReopenClosedTab: Bool {
        browser.selectedSpace?.archivedTabs.isEmpty == false
    }

    @discardableResult
    func toggleSelectedTabPinned() -> TabID? {
        guard let tab = browser.selectedTab else { return nil }
        let destination: TabPlacement = tab.placement == .pinned ? .current : .pinned
        guard browser.moveTab(tab.id, to: destination) else { return nil }
        synchronizePages()
        return tab.id
    }

    @discardableResult
    func archiveSelectedTab() -> TabID? {
        guard let tabID = browser.archiveSelectedTab() else { return nil }
        synchronizePages()
        return tabID
    }

    @discardableResult
    func dismissSelectedTab() -> TabID? {
        guard let selectedTab = browser.selectedTab else { return nil }
        switch BrowserTabDismissalPolicy.action(
            for: selectedTab,
            tabCount: orderedTabs.count
        ) {
        case .closeTab:
            if selectedTab.isStartPage {
                browser.closeTab(selectedTab.id)
                synchronizePages()
                return selectedTab.id
            }
            return archiveSelectedTab()
        case .unloadPage:
            browser.selectDismissalFallback(afterDismissing: selectedTab.id)
            pages.unloadPage(for: selectedTab.id)
            synchronizePages()
            return selectedTab.id
        case .closeWindow:
            return nil
        }
    }

    @discardableResult
    func duplicateSelectedTab() -> TabID? {
        guard let tabID = browser.duplicateSelectedTab() else { return nil }
        synchronizePages()
        return tabID
    }

    @discardableResult
    func reopenClosedTab() -> TabID? {
        guard
            let archived = browser.selectedSpace?.archivedTabs.max(
                by: { $0.archivedAt < $1.archivedAt }
            )
        else { return nil }
        browser.restoreArchivedTab(archived.id)
        browser.selectTab(archived.id)
        synchronizePages()
        return archived.id
    }

    func cleanupCurrentTabs() {
        browser.cleanupCurrentTabs()
        synchronizePages()
    }

    @discardableResult
    func selectPreviousTab() -> TabID? {
        selectTab(offset: -1)
    }

    @discardableResult
    func selectNextTab() -> TabID? {
        selectTab(offset: 1)
    }

    @discardableResult
    func selectMostRecentTab() -> TabID? {
        guard let selectedID = browser.selectedTab?.id,
            let recent =
                orderedTabs
                .filter({ $0.id != selectedID })
                .max(by: { $0.lastActivatedAt < $1.lastActivatedAt })
        else {
            return nil
        }
        return selectTab(recent.id)
    }

    @discardableResult
    func selectTab(at index: Int) -> TabID? {
        guard orderedTabs.indices.contains(index) else { return nil }
        return selectTab(orderedTabs[index].id)
    }

    @discardableResult
    func selectPreviousSpace() -> SpaceID? {
        selectSpace(.previous)
    }

    @discardableResult
    func selectNextSpace() -> SpaceID? {
        selectSpace(.next)
    }

    @discardableResult
    func selectSpace(at index: Int) -> SpaceID? {
        guard browser.session.spaces.indices.contains(index) else { return nil }
        let id = browser.session.spaces[index].id
        browser.selectSpace(id)
        synchronizePages()
        return id
    }

    private func selectTab(offset: Int) -> TabID? {
        guard let id = browser.selectAdjacentTab(offset: offset) else { return nil }
        synchronizePages()
        return id
    }

    private func selectTab(_ id: TabID) -> TabID? {
        browser.selectTab(id)
        synchronizePages()
        return id
    }

    private func selectSpace(_ direction: BrowserSpaceSwipeDirection) -> SpaceID? {
        guard let id = browser.selectAdjacentSpace(direction) else { return nil }
        synchronizePages()
        return id
    }

    // MARK: - Split View

    var presentedSplitMembers: [BrowserTab] {
        guard let space = browser.selectedSpace else { return [] }
        return space.presentedSplitMembers(for: space.selectedTabID)
    }

    var isSelectedTabInSplit: Bool {
        presentedSplitMembers.count > 1
    }

    var canSplitWithNextTab: Bool {
        browser.nextSplitJoinCandidate != nil
    }

    /// Moves focus one card along the presented run and wraps at both ends.
    ///
    /// Wrapping, unlike the toolbar swipe: a repeated chord reads as cycling
    /// through the cards, where a repeated spatial gesture reads as a direction
    /// and should stop at the edge.
    ///
    /// Focus is selection, so this is `selectTab` and nothing else — the toolbar,
    /// find bar, and every page command follow the pipeline they already followed
    /// before splits existed.
    @discardableResult
    func focusAdjacentSplitCard(offset: Int) -> TabID? {
        let members = presentedSplitMembers
        guard members.count > 1,
            let selectedTabID = browser.selectedSpace?.selectedTabID,
            let index = members.firstIndex(where: { $0.id == selectedTabID })
        else { return nil }
        let count = members.count
        let wrappedIndex = (index + offset % count + count) % count
        return selectTab(members[wrappedIndex].id)
    }

    /// Adds the next eligible tab in the selected tab's own section to its split,
    /// creating the group when there is none yet.
    @discardableResult
    func splitWithNextTab() -> TabID? {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID,
            let candidate = browser.nextSplitJoinCandidate,
            browser.addTabToSplit(
                BrowserTabDragItem(
                    tabID: candidate.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                ),
                joining: selectedTabID,
                at: nil
            )
        else { return nil }
        synchronizePages()
        return candidate.id
    }

    /// Whether the focused card has anywhere to go `offset` slots along its run.
    func canMoveFocusedSplitCard(offset: Int) -> Bool {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID
        else { return false }
        return browser.canMoveSplitMember(
            selectedTabID,
            by: offset,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    /// Slides the focused card along its run.
    ///
    /// No `synchronizePages()`: the selection and the presented set are both
    /// unchanged, so there is nothing for the pool to reconcile — only the
    /// column order the carousel reads back out of the session.
    @discardableResult
    func moveFocusedSplitCard(offset: Int) -> TabID? {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID,
            browser.moveSplitMember(
                selectedTabID,
                by: offset,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return nil }
        return selectedTabID
    }

    /// Drops the focused card out of its split and leaves it an ordinary tab.
    @discardableResult
    func removeSelectedTabFromSplit() -> TabID? {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID,
            browser.removeTabFromSplit(
                selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return nil }
        synchronizePages()
        return selectedTabID
    }

    /// "Separate All Tabs": every card in the presented split becomes a tab.
    @discardableResult
    func separateSplitTabs() -> TabID? {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID,
            browser.dissolveSplit(
                containing: selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return nil }
        synchronizePages()
        return selectedTabID
    }

    private func synchronizePages() {
        pages.reconcile(session: browser.session)
        pages.select(session: browser.session)
    }
}
