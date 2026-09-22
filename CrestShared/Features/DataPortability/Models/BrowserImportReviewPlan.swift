import Foundation

struct BrowserImportReviewPlan: Codable, Equatable, Sendable {
    enum ValidationError: LocalizedError, Equatable, Sendable {
        case noIncludedSpaces

        var errorDescription: String? {
            switch self {
            case .noIncludedSpaces:
                String(localized: "Choose at least one Space to import.")
            }
        }
    }

    private(set) var spaces: [BrowserImportSpaceReview]
    private var destinationCustomizations: [SpaceID: BrowserImportSpaceCustomization]

    /// The review a person starts from. The core matches each imported Space
    /// to the existing Space with the same name and leaves out tabs it already
    /// holds; when the core cannot answer, everything imports into new Spaces.
    init(imported: BrowserPortableImport, existing: BrowserSession) {
        let destinationSpaces =
            existing.hasDisposableSeedState
            ? []
            : existing.spaces
        destinationCustomizations = Dictionary(
            uniqueKeysWithValues: destinationSpaces.map {
                ($0.id, BrowserImportSpaceCustomization(space: $0))
            }
        )
        let suggestions = BrowserCoreWorkspaceImport.reviewSuggestions(sources: imported.spaces, existing: existing)
        spaces = imported.spaces.enumerated().map { index, sourceSpace in
            let suggestion = suggestions?[index]
            let matchingSpace = suggestion?.destinationID.flatMap { existing.space(id: $0) }
            return BrowserImportSpaceReview(
                sourceSpace: sourceSpace,
                destination: matchingSpace.map { .existing($0.id) } ?? .newSpace,
                customization: BrowserImportSpaceCustomization(
                    space: matchingSpace ?? sourceSpace
                ),
                includedTabIDs: suggestion?.includedTabIDs ?? Set(sourceSpace.tabs.map(\.id)),
                duplicateTabIDs: suggestion?.duplicateTabIDs ?? [],
                placementOverrides: [:],
                spaceInclusionOverride: nil,
                passwordInclusionOverride: nil
            )
        }
    }

    var hasIncludedSpaces: Bool {
        spaces.contains(where: \.isIncluded)
    }

    mutating func setDestination(
        _ destination: BrowserImportDestination,
        for sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].destination = destination
        switch destination {
        case .newSpace:
            spaces[index].customization = BrowserImportSpaceCustomization(
                space: spaces[index].sourceSpace
            )
        case .existing(let destinationID):
            if let customization = destinationCustomizations[destinationID] {
                spaces[index].customization = customization
            }
        }
    }

    mutating func setTab(
        _ tabID: TabID,
        isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }),
            spaces[index].sourceSpace.contains(tabID)
        else { return }
        if isIncluded {
            spaces[index].spaceInclusionOverride = true
            spaces[index].includedTabIDs.insert(tabID)
        } else {
            spaces[index].includedTabIDs.remove(tabID)
        }
    }

    mutating func setTabs(
        _ tabIDs: Set<TabID>,
        isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        let validTabIDs = Set(spaces[index].sourceSpace.tabs.map(\.id))
        let changedTabIDs = tabIDs.intersection(validTabIDs)
        if isIncluded {
            spaces[index].spaceInclusionOverride = true
            spaces[index].includedTabIDs.formUnion(changedTabIDs)
        } else {
            spaces[index].includedTabIDs.subtract(changedTabIDs)
        }
    }

    mutating func setSpace(
        _ sourceSpaceID: SpaceID,
        isIncluded: Bool
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].spaceInclusionOverride = isIncluded
        if isIncluded {
            let allTabIDs = Set(spaces[index].sourceSpace.tabs.map(\.id))
            spaces[index].includedTabIDs = allTabIDs.subtracting(
                spaces[index].duplicateTabIDs
            )
        } else {
            spaces[index].includedTabIDs.removeAll()
        }
    }

    mutating func setPasswords(
        _ isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].passwordInclusionOverride = isIncluded
    }

    mutating func setPlacement(
        _ placement: TabPlacement,
        for tabID: TabID,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }),
            spaces[index].sourceSpace.contains(tabID)
        else { return }
        spaces[index].spaceInclusionOverride = true
        spaces[index].placementOverrides[tabID] = placement
        spaces[index].includedTabIDs.insert(tabID)
    }

    mutating func setSpaceIdentity(
        name: String,
        symbol: String,
        for sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].customization.name = name
        spaces[index].customization.symbol = symbol
    }

    mutating func setSpaceBranding(
        _ branding: BrowserSpaceBranding,
        for sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].customization.branding = branding.normalized()
    }

    /// What the current choices mean against `existing`, answered by the core
    /// in one pass. Empty when the core cannot answer; the import itself still
    /// enforces the pinned limit.
    func analysis(in existing: BrowserSession) -> BrowserImportReviewAnalysis {
        BrowserCoreWorkspaceImport.reviewAnalysis(self, existing: existing) ?? BrowserImportReviewAnalysis()
    }

    func overflowTabIDs(in existing: BrowserSession) -> Set<TabID> {
        analysis(in: existing).overflowTabIDs
    }

    func preview(mergingInto existing: BrowserSession) throws -> BrowserSession {
        return try BrowserCoreWorkspaceImport.preview(BrowserCoreWorkspaceImport.review(self), existing: existing)
    }
}

/// The core's reading of an import review: tabs their destination already
/// holds, destination tabs each imported Space matches, and pinned tabs past
/// their destination's limit.
struct BrowserImportReviewAnalysis: Equatable {
    var duplicateTabIDs: Set<TabID> = []
    var overflowTabIDs: Set<TabID> = []
    var matchedTabIDsBySourceSpace: [SpaceID: Set<TabID>] = [:]

    func matchedTabIDs(for sourceSpaceID: SpaceID) -> Set<TabID> {
        matchedTabIDsBySourceSpace[sourceSpaceID] ?? []
    }
}
