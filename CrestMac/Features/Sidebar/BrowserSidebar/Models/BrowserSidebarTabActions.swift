import Foundation

@MainActor
struct BrowserSidebarTabActions {
    let assignment: BrowserSpaceRuntimeAssignment
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

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
        pages.reconcile(session: browser.session)
        pages.select(session: browser.session)
        return true
    }

    func pullNewIcon(for tabID: TabID) {
        Task {
            guard
                let pulled = await pages.pullFavicon(
                    for: tabID,
                    matching: assignment
                )
            else { return }
            guard
                let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                    matching: assignment,
                    in: browser,
                    accessController: spaceAccess
                ),
                space.tabs.contains(where: { $0.id == tabID })
            else { return }
            browser.setTabFavicon(
                pulled.data,
                iconAccent: pulled.iconAccent,
                for: tabID,
                matching: assignment
            )
        }
    }

    func restoreSavedLocation(for tabID: TabID) {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            ),
            let tab = space.tabs.first(where: { $0.id == tabID }),
            tab.isAwayFromSavedLocation,
            tab.savedSiteURL != nil
        else { return }
        browser.selectTab(tabID)
        pages.select(session: browser.session)
        let runtimeAssignment = BrowserTabRuntimeAssignment(
            tabID: tabID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
        guard let page = pages.activePage(matching: runtimeAssignment),
            let url = browser.restoreTabSavedLocation(
                tabID,
                in: assignment.spaceID
            )
        else { return }
        page.load(url)
    }
}
