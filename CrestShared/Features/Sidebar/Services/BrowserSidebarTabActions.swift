import Foundation

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
            TabID,
            BrowserSpaceRuntimeAssignment
        ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?

    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        syncPagesAfterMutation: @escaping @MainActor () -> Void,
        pullFavicon:
            @escaping @MainActor (
                TabID,
                BrowserSpaceRuntimeAssignment
            ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?
    ) {
        self.assignment = assignment
        self.browser = browser
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
    func pullNewIcon(for tabID: TabID) async -> Bool {
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
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            ) != nil,
            browser.clearCurrentTabs(matching: assignment)
        else { return false }
        syncPagesAfterMutation()
        return true
    }

    private func ownsUnlockedTab(_ tabID: TabID) -> Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return space.tabs.contains(where: { $0.id == tabID })
    }
}
