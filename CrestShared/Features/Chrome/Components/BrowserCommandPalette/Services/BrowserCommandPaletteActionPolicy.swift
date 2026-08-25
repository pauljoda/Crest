@MainActor
enum BrowserCommandPaletteActionPolicy {
    static func isSourceAvailable(
        _ source: BrowserTabRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> Bool {
        selectedSource(
            matching: source,
            in: browser,
            accessController: accessController
        ) != nil
    }

    static func target(
        _ target: BrowserTabRuntimeAssignment,
        from source: BrowserTabRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> (space: BrowserSpace, tab: BrowserTab)? {
        guard
            target.spaceID == source.spaceID,
            target.profileID == source.profileID,
            selectedSource(
                matching: source,
                in: browser,
                accessController: accessController
            ) != nil,
            let space = browser.space(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: target.spaceID,
                    profileID: target.profileID
                )
            ),
            !accessController.isLocked(space),
            let tab = space.tabs.first(where: { $0.id == target.tabID })
        else { return nil }
        return (space, tab)
    }

    private static func selectedSource(
        matching source: BrowserTabRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> (space: BrowserSpace, tab: BrowserTab)? {
        guard browser.session.selectedSpaceID == source.spaceID,
            let space = browser.space(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: source.spaceID,
                    profileID: source.profileID
                )
            ),
            !accessController.isLocked(space),
            space.selectedTabID == source.tabID,
            let tab = space.tabs.first(where: { $0.id == source.tabID })
        else { return nil }
        return (space, tab)
    }
}
