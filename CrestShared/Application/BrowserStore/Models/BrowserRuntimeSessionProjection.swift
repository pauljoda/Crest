struct BrowserRuntimeSessionProjection: Equatable, Sendable {
    let tabIconState: BrowserTabIconSessionState
    let contentBlockingState: BrowserContentBlockingSessionState
    let credentialAccessState: [SpaceID: Bool]

    init(session: BrowserSession) {
        var tabIconItems: [BrowserTabIconSessionItem] = []
        var contentBlockingPolicies: [SpaceID: ContentBlockingPolicy] = [:]
        var credentialAccessBySpaceID: [SpaceID: Bool] = [:]

        for space in session.spaces {
            tabIconItems.reserveCapacity(tabIconItems.count + space.tabs.count)

            for tab in space.tabs {
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

            contentBlockingPolicies[space.id] =
                space.browsingPreferences.contentBlockingPolicy
            credentialAccessBySpaceID[space.id] =
                space.credentialPreferences.isEnabled
        }

        tabIconState = BrowserTabIconSessionState(items: tabIconItems)
        contentBlockingState = BrowserContentBlockingSessionState(
            policiesBySpaceID: contentBlockingPolicies
        )
        credentialAccessState = credentialAccessBySpaceID
    }
}
