enum BrowserImportReviewNavigation {
    static func nextSpaceID(
        after currentID: SpaceID?,
        in spaceIDs: [SpaceID]
    ) -> SpaceID? {
        guard !spaceIDs.isEmpty else { return nil }
        guard let currentID,
            let index = spaceIDs.firstIndex(of: currentID)
        else {
            return spaceIDs.first
        }
        let nextIndex = spaceIDs.index(after: index)
        return nextIndex < spaceIDs.endIndex ? spaceIDs[nextIndex] : nil
    }

    static func isFinalSpace(
        _ currentID: SpaceID?,
        in spaceIDs: [SpaceID]
    ) -> Bool {
        guard let currentID, let last = spaceIDs.last else { return false }
        return currentID == last
    }
}
