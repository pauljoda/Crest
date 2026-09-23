struct BrowserTabSelectionHistory: Equatable, Sendable {
    private var tabIDsBySpaceID: [SpaceID: [TabID]] = [:]

    init(session: BrowserSession, selection: BrowserStoreSelection) {
        reconcile(session: session, selection: selection)
    }

    /// Records each Space's shown tab as its most recent choice.
    mutating func reconcile(session: BrowserSession, selection: BrowserStoreSelection) {
        let availableSpaceIDs = Set(session.spaces.map(\.id))
        tabIDsBySpaceID = tabIDsBySpaceID.filter {
            availableSpaceIDs.contains($0.key)
        }

        for space in session.spaces {
            var history = tabIDsBySpaceID[space.id, default: []]

            if let selectedTabID = selection.selectedTabID(in: space.id),
                space.contains(selectedTabID)
            {
                history.removeAll { $0 == selectedTabID }
                history.append(selectedTabID)
            }

            tabIDsBySpaceID[space.id] = history
        }
    }

    mutating func fallbackTabID(
        afterDismissing dismissedTabID: TabID,
        in spaceID: SpaceID,
        availableTabIDs: Set<TabID>
    ) -> TabID? {
        var history = tabIDsBySpaceID[spaceID, default: []]
        history.removeAll { $0 == dismissedTabID }
        tabIDsBySpaceID[spaceID] = history
        guard let fallbackTabID = history.last,
            availableTabIDs.contains(fallbackTabID)
        else {
            tabIDsBySpaceID[spaceID] = []
            return nil
        }
        return fallbackTabID
    }
}
