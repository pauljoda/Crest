struct BrowserContentBlockingUpdate {
    let state: BrowserContentBlockingSessionState
    private let changedSpaceIDs: Set<SpaceID>

    init(
        state: BrowserContentBlockingSessionState,
        previousState: BrowserContentBlockingSessionState?
    ) {
        self.state = state
        changedSpaceIDs = Set(
            state.policiesBySpaceID.compactMap { spaceID, policy in
                guard let previous = previousState?.policiesBySpaceID[spaceID], previous != policy else {
                    return nil
                }
                return spaceID
            }
        )
    }

    func policy(for spaceID: SpaceID) -> ContentBlockingPolicy {
        state.policiesBySpaceID[spaceID] ?? .off
    }

    func activation(for spaceID: SpaceID, isPresented: Bool) -> BrowserContentRuleListActivation {
        isPresented && changedSpaceIDs.contains(spaceID) ? .immediately : .onNextNavigation
    }
}
