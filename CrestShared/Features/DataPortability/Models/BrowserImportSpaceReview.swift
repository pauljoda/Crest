struct BrowserImportSpaceReview: Codable, Equatable, Sendable, Identifiable {
    var sourceSpace: BrowserSpace
    var destination: BrowserImportDestination
    var customization: BrowserImportSpaceCustomization
    var includedTabIDs: Set<TabID>
    var duplicateTabIDs: Set<TabID>
    var placementOverrides: [TabID: TabPlacement]
    var spaceInclusionOverride: Bool?
    var passwordInclusionOverride: Bool?

    var id: SpaceID { sourceSpace.id }
    var isIncluded: Bool { spaceInclusionOverride ?? true }
    var includesPasswords: Bool {
        isIncluded && (passwordInclusionOverride ?? true)
    }

    func placement(for tab: BrowserTab) -> TabPlacement {
        placementOverrides[tab.id] ?? tab.placement
    }
}
