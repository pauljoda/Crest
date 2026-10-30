import Foundation

// MARK: - Types

/// The Space Tidy started in was switched away from or locked before it finished.
struct TidySpaceNoLongerShown: Error {}

/// The mutations a sidebar row performs on the tabs of one Space.
///
/// Both shells ask for the same work behind the same guard: the Space this
/// instance was built for must still be the selected, unlocked one, and the tab
/// must still be in it. What the shells do not share is what the page layer
/// owes once the session changes — the windowed shell keeps a pool of cards in
/// step, the compact shell's single page follows the session on its own — so
/// the page-facing steps arrive as closures each shell binds in its own
/// convenience initializer.
@MainActor
struct BrowserSidebarTabActions {
    let assignment: BrowserSpaceRuntimeAssignment
    private let reorderState: BrowserSidebarReorderState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// Brings the page layer back in step with a session this type just
    /// rewrote. The windowed shell reconciles its pool and re-presents the
    /// selection; the compact shell has nothing to do.
    private let syncPagesAfterMutation: @MainActor () -> Void

    /// Asks a resident page for a fresh favicon. `nil` when the tab holds no
    /// page, has moved, or the page cannot produce one.
    private let pullFavicon:
        @MainActor (
            UUID,
            BrowserSpaceRuntimeAssignment
        ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?

    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        reorderState: BrowserSidebarReorderState,
        spaceAccess: BrowserSpaceAccessController,
        syncPagesAfterMutation: @escaping @MainActor () -> Void,
        pullFavicon:
            @escaping @MainActor (
                UUID,
                BrowserSpaceRuntimeAssignment
            ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?
    ) {
        self.assignment = assignment
        self.browser = browser
        self.reorderState = reorderState
        self.spaceAccess = spaceAccess
        self.syncPagesAfterMutation = syncPagesAfterMutation
        self.pullFavicon = pullFavicon
    }

    /// Replaces a tab's favicon with whatever its page reports now.
    ///
    /// The ownership check runs on both sides of the pull on purpose: a Space
    /// can be reselected, relocked, or have its profile replaced while the
    /// request is in flight, and an icon written after that would land on a tab
    /// this sidebar no longer speaks for.
    @discardableResult
    func pullNewIcon(for tabID: UUID) async -> Bool {
        guard ownsUnlockedTab(tabID),
            let pulled = await pullFavicon(tabID, assignment),
            ownsUnlockedTab(tabID)
        else { return false }
        return browser.setTabFavicon(
            pulled.data,
            iconAccent: pulled.iconAccent,
            for: tabID,
            matching: assignment
        )
    }

    /// Closes the Space's current tabs, leaving its pinned and saved tabs be.
    @discardableResult
    func clearCurrentTabs() -> Bool {
        guard
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            browser.clearCurrentTabs(matching: assignment)
        else { return false }
        syncPagesAfterMutation()
        return true
    }

    /// Files the Space's loose open tabs under headers with the on-device
    /// model. Throws when the Space stops being the selected, unlocked one,
    /// when the model fails, or when the core refuses the headers because the
    /// tabs changed while they were being made. Does nothing when Tidy was
    /// turned off or Apple Intelligence became unavailable meanwhile, and a
    /// tab whose page changed meanwhile stays loose.
    func tidyCurrentTabs() async throws {
        guard let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) else {
            throw TidySpaceNoLongerShown()
        }
        let candidates = OnDeviceTabTidyingService.candidates(in: space)
        let headers = try await OnDeviceTabTidyingService().headers(for: candidates)
        guard let shownSpace = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
        else {
            throw TidySpaceNoLongerShown()
        }
        guard OnDeviceTabTidyingService.isReady else { return }
        try browser.tidySessionTabs(
            folders: OnDeviceTabTidyingService.proposals(headers, unchangedSince: candidates, in: shownSpace),
            in: assignment.spaceID)
        syncPagesAfterMutation()
    }

    /// Closes a header Tidy made by closing the tabs under it, as selecting
    /// and closing them does, and the header goes with its last tabs. A header
    /// left without tabs is deleted.
    @discardableResult
    func closeTidyHeader(_ folderID: UUID) -> Bool {
        guard let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) else {
            return false
        }
        let tabIDs = space.tabIDs(inFolder: folderID)
        guard !tabIDs.isEmpty else { return browser.deleteSessionFolder(folderID, in: assignment.spaceID) }
        guard let request = BrowserSidebarSelection.capture(tabIDs.map(BrowserSelectionItemID.tab), in: browser) else {
            return false
        }
        return BrowserTabBatchActions(browser: browser, spaceAccess: spaceAccess).perform(
            browser.closing(request), for: request)
    }

    /// Routes an empty-background gesture through the host's existing New Tab
    /// command. Recheck ownership when the gesture ends, after any Space change.
    @discardableResult
    func openNewTab(_ command: () -> Void) -> Bool {
        guard !reorderState.isDragging,
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
        else { return false }
        command()
        return true
    }

    private func ownsUnlockedTab(_ tabID: UUID) -> Bool {
        guard
            let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
        else { return false }
        return space.tabs.model(tabID) != nil
    }
}
