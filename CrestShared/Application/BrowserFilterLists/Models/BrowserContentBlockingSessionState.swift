struct BrowserContentBlockingSessionState: Equatable, Sendable {
    let policiesBySpaceID: [SpaceID: ContentBlockingPolicy]

    init(policiesBySpaceID: [SpaceID: ContentBlockingPolicy]) {
        self.policiesBySpaceID = policiesBySpaceID
    }

    init(session: BrowserSession) {
        self.init(
            policiesBySpaceID: Dictionary(
                uniqueKeysWithValues: session.spaces.map { space in
                    (space.id, space.browsingPreferences.contentBlockingPolicy)
                }
            )
        )
    }
}
