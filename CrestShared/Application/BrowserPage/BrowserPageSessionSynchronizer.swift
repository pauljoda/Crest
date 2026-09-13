import Foundation

@MainActor
struct BrowserPageSessionSynchronizer {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    func synchronize(_ metadata: BrowserPageMetadata, matching source: BrowserTabRuntimeAssignment) -> String? {
        guard selectedSpace(matching: source) != nil else { return nil }
        browser.updateSelectedTabFromPage(
            url: metadata.displayURL, title: metadata.displayTitle,
            faviconData: metadata.faviconData, iconAccent: metadata.iconAccent
        )
        return (metadata.displayURL ?? browser.selectedTab?.url)?.absoluteString ?? ""
    }

    func recordCompletedNavigation(
        _ metadata: BrowserPageMetadata, matching source: BrowserTabRuntimeAssignment
    ) -> BrowserSpace? {
        guard let space = selectedSpace(matching: source), let url = metadata.url else { return nil }
        browser.recordVisit(url: url, title: metadata.title, in: space.id)
        return browser.selectedSpace
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
