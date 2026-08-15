struct BrowserSpacePagerRecenterRequest: Equatable, Sendable {
    let revision: UInt
    let spaceID: SpaceID

    func isCurrent(
        revision: UInt,
        selectedSpaceID: SpaceID,
        isInteractionLocked: Bool
    ) -> Bool {
        self.revision == revision
            && spaceID == selectedSpaceID
            && !isInteractionLocked
    }
}
