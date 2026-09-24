import Foundation

@MainActor
struct BrowserPageSessionSynchronizer {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// The address the window's address field shows for the page of the tab
    /// it shows, or nil while that tab is not the one the window shows or its
    /// Space is locked.
    func address(of metadata: BrowserPageMetadata, matching source: BrowserTabRuntimeAssignment) -> String? {
        guard selectedSpace(matching: source) != nil else { return nil }
        return (metadata.displayURL ?? browser.selectedTab?.url)?.absoluteString ?? ""
    }

    private func selectedSpace(matching source: BrowserTabRuntimeAssignment) -> BrowserSpace? {
        guard let space = browser.selectedSpace,
            space.id == source.spaceID, space.profile.id == source.profileID,
            browser.selectedTab?.id == source.tabID,
            !spaceAccess.isLocked(space)
        else { return nil }
        return space
    }
}
