import Foundation

// MARK: - Types

/// The Space Tidy started in was switched away from or locked before it
/// finished.
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

    /// Archives the Space's open tabs, leaving its pinned and saved tabs be,
    /// and the tab the window shows there when `keepingShownTab`.
    @discardableResult
    func clearCurrentTabs(keepingShownTab: Bool) -> Bool {
        guard
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            browser.clearCurrentTabs(matching: assignment, keepingShownTab: keepingShownTab)
        else { return false }
        syncPagesAfterMutation()
        return true
    }

    /// Whether Tidy is ready and the Space is the one shown, unlocked, with
    /// enough loose web pages to sort.
    var canTidy: Bool {
        guard TabTidying.shared.isReady,
            let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
        else { return false }
        return TabTidying.candidateCount(in: space, of: browser) >= TabTidying.minimumLooseTabCount
    }

    /// Starts a Tidy of the Space's loose open tabs, unless one is under way.
    func startTidying() {
        TabTidying.shared.run(in: assignment.spaceID) { try await tidyCurrentTabs() }
    }

    /// Files the Space's loose open tabs into Groups by topic, with Apple's
    /// on-device model. Throws when the Space stops being the selected,
    /// unlocked one, when the model fails, or when the core refuses because
    /// the tabs changed meanwhile. Does nothing when Tidy was turned off
    /// meanwhile, even if it is on again, or Apple Intelligence went away, and
    /// a tab whose page changed meanwhile stays loose.
    func tidyCurrentTabs() async throws {
        guard let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) else {
            throw TidySpaceNoLongerShown()
        }
        let tidying = TabTidying.shared
        let generation = tidying.generation
        let candidates = TabTidying.candidates(in: space, of: browser)
        let topics = try await tidying.topics(for: candidates)
        guard let shown = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) else {
            throw TidySpaceNoLongerShown()
        }
        let unchanged = TabTidying.topics(topics, unchangedSince: candidates, in: shown, of: browser)
        guard tidying.isReady, tidying.generation == generation, !unchanged.isEmpty else { return }
        try browser.tidySessionTabs(into: unchanged, in: assignment.spaceID)
        syncPagesAfterMutation()
    }

    /// Whether the Space is the one shown, unlocked, and has a folder open to
    /// collapse.
    var canCollapseAllFolders: Bool {
        browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
            && browser.allows(.collapseAllFolders)
    }

    /// Collapses every open folder of the Space, however deep, leaving its
    /// tabs be.
    @discardableResult
    func collapseAllFolders() -> Bool {
        browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
            && browser.collapseAllFolders(matching: assignment)
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
        return space.shownTab(tabID) != nil
    }
}
