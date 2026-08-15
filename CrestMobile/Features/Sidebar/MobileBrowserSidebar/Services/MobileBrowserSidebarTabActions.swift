import Foundation

@MainActor
struct MobileBrowserSidebarTabActions {
    let assignment: BrowserSpaceRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    private let pullFavicon:
        @MainActor (
            TabID,
            BrowserSpaceRuntimeAssignment
        ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?

    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.assignment = assignment
        self.browser = browser
        self.spaceAccess = spaceAccess
        pullFavicon = { tabID, assignment in
            await pages.pullFavicon(for: tabID, matching: assignment)
        }
    }

    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        pullFavicon:
            @escaping @MainActor (
                TabID,
                BrowserSpaceRuntimeAssignment
            ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?
    ) {
        self.assignment = assignment
        self.browser = browser
        self.spaceAccess = spaceAccess
        self.pullFavicon = pullFavicon
    }

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
