/// A window retains identities only. Its browsing data always comes from its
/// family, and a known Space without a selected tab is intentionally empty.
struct BrowserStoreSelection: Equatable {
    var selectedSpaceID: SpaceID
    private var knownSpaceIDs: Set<SpaceID>
    private var selectedTabIDsBySpace: [SpaceID: TabID]

    init(session: BrowserSession) {
        selectedSpaceID = session.selectedSpaceID
        knownSpaceIDs = Set(session.spaces.map(\.id))
        selectedTabIDsBySpace = Dictionary(
            session.spaces.compactMap { space in
                space.selectedTabID.map { (space.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func applying(to shared: BrowserSession) -> BrowserSession {
        var projection = shared
        projection.selectedSpaceID = selectedSpaceID
        for index in projection.spaces.indices {
            let spaceID = projection.spaces[index].id
            guard knownSpaceIDs.contains(spaceID),
                projection.spaces[index].selectedTabID != selectedTabIDsBySpace[spaceID]
            else { continue }
            projection.spaces[index].selectedTabID = selectedTabIDsBySpace[spaceID]
        }
        return projection
    }

    func selectedSpace(in shared: BrowserSession) -> BrowserSpace? {
        guard var space = shared.space(id: selectedSpaceID) else { return nil }
        if knownSpaceIDs.contains(space.id) {
            space.selectedTabID = selectedTabIDsBySpace[space.id]
        }
        return space
    }

    mutating func reconcile(using shared: BrowserSession, excluding deletingSpaceIDs: Set<SpaceID>) {
        let availableSpaceIDs = Set(shared.spaces.map(\.id))
        selectedTabIDsBySpace = selectedTabIDsBySpace.filter { spaceID, tabID in
            shared.space(id: spaceID)?.contains(tabID) == true
        }
        for space in shared.spaces where !knownSpaceIDs.contains(space.id) {
            selectedTabIDsBySpace[space.id] = space.selectedTabID
        }
        knownSpaceIDs = availableSpaceIDs
        guard !availableSpaceIDs.contains(selectedSpaceID) || deletingSpaceIDs.contains(selectedSpaceID) else { return }
        if availableSpaceIDs.contains(shared.selectedSpaceID), !deletingSpaceIDs.contains(shared.selectedSpaceID) {
            selectedSpaceID = shared.selectedSpaceID
        } else if let fallback = shared.spaces.first(where: { !deletingSpaceIDs.contains($0.id) }) {
            selectedSpaceID = fallback.id
        }
    }
}
