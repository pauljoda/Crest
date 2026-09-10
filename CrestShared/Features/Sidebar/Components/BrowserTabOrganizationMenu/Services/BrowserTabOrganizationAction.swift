import Foundation

@MainActor
struct BrowserTabOrganizationAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    func linkURL(for assignment: BrowserTabRuntimeAssignment) -> URL? {
        let spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID, profileID: assignment.profileID)
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: spaceAssignment, in: browser, accessController: spaceAccess),
            let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            tab.isWebPage
        else { return nil }
        if let provider = browser.tabLinkProvider {
            return provider.linkURL(for: tab, in: space)
        }
        return tab.url
    }

    @discardableResult
    func copyLinkURL(for assignment: BrowserTabRuntimeAssignment) -> Bool {
        BrowserPageLinkClipboard.copy(linkURL(for: assignment))
    }

    @discardableResult
    func close(
        _ assignment: BrowserTabRuntimeAssignment,
        expectedPlacement: TabPlacement
    ) -> Bool {
        guard expectedPlacement == .current,
            let spaceAssignment = liveSpaceAssignment(
                for: assignment,
                expectedPlacement: expectedPlacement
            )
        else { return false }
        return browser.closeTab(assignment.tabID, matching: spaceAssignment)
    }

    @discardableResult
    func delete(
        _ assignment: BrowserTabRuntimeAssignment,
        expectedPlacement: TabPlacement
    ) -> Bool {
        guard expectedPlacement != .current,
            let spaceAssignment = liveSpaceAssignment(
                for: assignment,
                expectedPlacement: expectedPlacement
            )
        else { return false }
        return browser.deleteTab(assignment.tabID, matching: spaceAssignment)
    }

    private func liveSpaceAssignment(
        for assignment: BrowserTabRuntimeAssignment,
        expectedPlacement: TabPlacement
    ) -> BrowserSpaceRuntimeAssignment? {
        let spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: spaceAssignment,
                in: browser,
                accessController: spaceAccess
            ),
            let tab = space.tabs.first(where: { $0.id == assignment.tabID }),
            tab.placement == expectedPlacement
        else { return nil }
        return spaceAssignment
    }
}
