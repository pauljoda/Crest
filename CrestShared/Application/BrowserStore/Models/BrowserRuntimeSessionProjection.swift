struct BrowserRuntimeSessionProjection: Equatable, Sendable {
    let extensionState: BrowserExtensionSessionState
    let tabIconState: BrowserTabIconSessionState
    let contentBlockingState: BrowserContentBlockingSessionState
    let credentialAccessState: [SpaceID: Bool]

    init(session: BrowserSession) {
        var extensionSpaces: [BrowserExtensionSpaceState] = []
        var tabIconItems: [BrowserTabIconSessionItem] = []
        var contentBlockingPolicies: [SpaceID: BrowserContentBlockingPolicy] = [:]
        var credentialAccessBySpaceID: [SpaceID: Bool] = [:]
        extensionSpaces.reserveCapacity(session.spaces.count)

        for space in session.spaces {
            var extensionTabs: [BrowserExtensionTabState] = []
            extensionTabs.reserveCapacity(space.tabs.count)
            tabIconItems.reserveCapacity(tabIconItems.count + space.tabs.count)

            for (index, tab) in space.tabs.enumerated() {
                extensionTabs.append(
                    BrowserExtensionTabState(
                        id: tab.id,
                        title: tab.title,
                        url: tab.url,
                        placement: tab.placement,
                        index: index,
                        isSelected: tab.id == space.selectedTabID
                    )
                )
                tabIconItems.append(
                    BrowserTabIconSessionItem(
                        id: tab.id,
                        url: tab.url,
                        faviconData: tab.faviconData,
                        faviconURL: tab.faviconURL,
                        iconAccent: tab.iconAccent,
                        iconMode: tab.iconMode,
                        symbol: tab.symbol
                    )
                )
            }

            extensionSpaces.append(
                BrowserExtensionSpaceState(id: space.id, tabs: extensionTabs)
            )
            contentBlockingPolicies[space.id] =
                space.browsingPreferences.contentBlockingPolicy
            credentialAccessBySpaceID[space.id] =
                space.credentialPreferences.isEnabled
        }

        extensionState = BrowserExtensionSessionState(
            selectedSpaceID: session.selectedSpaceID,
            spaces: extensionSpaces
        )
        tabIconState = BrowserTabIconSessionState(items: tabIconItems)
        contentBlockingState = BrowserContentBlockingSessionState(
            policiesBySpaceID: contentBlockingPolicies
        )
        credentialAccessState = credentialAccessBySpaceID
    }
}
