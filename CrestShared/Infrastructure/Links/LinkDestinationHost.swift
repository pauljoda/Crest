import Foundation

/// Context-menu destinations use the same tab-opening and access rules as the sidebar.
@MainActor
struct BrowserLinkDestinationHost {
    weak var browser: BrowserStore?
    weak var spaceAccess: BrowserSpaceAccessController?

    static let unavailable = BrowserLinkDestinationHost()

    func canOpenLink(from source: BrowserTabRuntimeAssignment) -> Bool {
        guard let browser, let spaceAccess,
            let space = browser.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: source.spaceID, profileID: source.profileID
                ), accessController: spaceAccess)
        else { return false }
        return space.tabs.model(source.tabID) != nil
    }

    func otherSpaces(from source: BrowserTabRuntimeAssignment) -> [SpaceModel] {
        guard canOpenLink(from: source), let browser, let spaceAccess else { return [] }
        return browser.availableTabMoveDestinationSpaces(
            from: BrowserSpaceRuntimeAssignment(
                spaceID: source.spaceID, profileID: source.profileID
            ), accessController: spaceAccess)
    }

    func selectionSearch(
        for text: String,
        from source: BrowserTabRuntimeAssignment
    ) -> BrowserSelectionSearchDestination? {
        guard canOpenLink(from: source), let browser,
            let search = try? browser.core.query(
                SelectionSearch(workspaceID: browser.family.workspaceID, spaceID: source.spaceID, text: text)),
            let url = search.url.flatMap(URL.init(string:))
        else { return nil }
        return BrowserSelectionSearchDestination(url: url, engineTitle: search.engineTitle, source: source)
    }

    @discardableResult
    func openLink(
        _ url: URL,
        from source: BrowserTabRuntimeAssignment,
        in destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard ExternalWebLink.accepts(url),
            canOpenLink(from: source), let browser, let spaceAccess,
            browser.unlockedSpace(matching: destination, accessController: spaceAccess) != nil
        else { return false }
        return browser.openNewTab(url: url, matching: destination) != nil
    }
}

struct BrowserSelectionSearchDestination: Equatable, Sendable {
    let url: URL
    /// The name of the engine that runs the search.
    let engineTitle: String
    let source: BrowserTabRuntimeAssignment
}
