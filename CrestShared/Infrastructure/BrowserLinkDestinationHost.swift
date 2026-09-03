import Foundation

/// Context-menu destinations use the same tab-opening and access rules as the sidebar.
@MainActor
struct BrowserLinkDestinationHost {
    weak var browser: BrowserStore?
    weak var spaceAccess: BrowserSpaceAccessController?

    static let unavailable = BrowserLinkDestinationHost()

    func canOpenLink(from source: BrowserTabRuntimeAssignment) -> Bool {
        guard let browser, let spaceAccess,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: source.spaceID, profileID: source.profileID
                ),
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return space.tabs.contains { $0.id == source.tabID }
    }

    func otherSpaces(from source: BrowserTabRuntimeAssignment) -> [BrowserSpace] {
        guard canOpenLink(from: source), let browser, let spaceAccess else { return [] }
        return BrowserSidebarAccessPolicy.availableTabMoveDestinationSpaces(
            from: BrowserSpaceRuntimeAssignment(
                spaceID: source.spaceID, profileID: source.profileID
            ),
            in: browser,
            accessController: spaceAccess
        )
    }

    @discardableResult
    func openLink(
        _ url: URL,
        from source: BrowserTabRuntimeAssignment,
        in destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard BrowserExternalURLPolicy.accepts(url),
            canOpenLink(from: source), let browser, let spaceAccess,
            BrowserSidebarAccessPolicy.unlockedSpace(
                matching: destination,
                in: browser,
                accessController: spaceAccess
            ) != nil
        else { return false }
        return browser.openNewTab(url: url, matching: destination) != nil
    }
}
