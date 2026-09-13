@MainActor
struct BrowserSettingsSpaceSelectionAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @discardableResult
    func select(_ id: SpaceID, matching source: BrowserTabRuntimeAssignment) -> BrowserTabRuntimeAssignment? {
        guard
            let sourceSpace = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID),
                in: browser, accessController: spaceAccess),
            sourceSpace.tabs.contains(where: { $0.id == source.tabID && $0.nativeContent == .settings }),
            let destination = BrowserSidebarAccessPolicy.availableSpaces(in: browser).first(where: { $0.id == id }),
            !spaceAccess.isLocked(destination)
        else { return nil }

        browser.selectSpace(id)
        guard let tabID = browser.openSettings() else { return nil }
        return BrowserTabRuntimeAssignment(tabID: tabID, spaceID: destination.id, profileID: destination.profile.id)
    }
}
