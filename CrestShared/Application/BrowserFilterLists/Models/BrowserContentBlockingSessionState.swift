struct BrowserContentBlockingSessionState: Equatable, Sendable {
    let policiesBySpaceID: [SpaceID: BrowserContentBlockingPolicy]

    init(policiesBySpaceID: [SpaceID: BrowserContentBlockingPolicy]) {
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
