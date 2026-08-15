enum BrowserLinkSettingsSpacePolicy {
    static func resolvedExternalSpaceID(
        preferredSpaceID: SpaceID?,
        spaces: [BrowserSpace],
        selectedSpaceID: SpaceID,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> SpaceID {
        if let preferredSpaceID,
            !unavailableSpaceIDs.contains(preferredSpaceID),
            spaces.contains(where: { $0.id == preferredSpaceID })
        {
            return preferredSpaceID
        }
        if !unavailableSpaceIDs.contains(selectedSpaceID),
            spaces.contains(where: { $0.id == selectedSpaceID })
        {
            return selectedSpaceID
        }
        return spaces.first {
            !unavailableSpaceIDs.contains($0.id)
        }?.id ?? selectedSpaceID
    }
}
