import Foundation

/// A person's review of an import: for each imported Space, whether it comes
/// in, where, under what name and look, which tabs and in which placements.
/// The core suggests where the review starts and says what it means; this
/// holds only the person's choices.
struct BrowserImportReviewPlan: Codable, Equatable, Sendable {
    private(set) var spaces: [BrowserImportSpaceReview]
    private var destinationCustomizations: [SpaceID: BrowserImportSpaceCustomization]

    /// The review a person starts from, as the core suggests it against
    /// `browser`'s workspace. When the core cannot answer, everything imports
    /// into new Spaces.
    @MainActor
    init(imported: BrowserPortableImport, in browser: BrowserStore) {
        let existing = browser.session
        let destinationSpaces =
            existing.hasDisposableSeedState
            ? []
            : existing.spaces
        destinationCustomizations = Dictionary(
            uniqueKeysWithValues: destinationSpaces.map {
                ($0.id, BrowserImportSpaceCustomization(space: $0))
            }
        )
        let suggestions =
            (try? browser.core.query(
                ImportReviewSuggestions(
                    workspaceID: browser.family.workspaceID, sources: imported.spaces.map(ImportReviewSpace.init))))?
            .spaces ?? []
        let suggested = Dictionary(suggestions.map { ($0.sourceSpaceID, $0) }, uniquingKeysWith: { first, _ in first })
        spaces = imported.spaces.map { sourceSpace in
            let suggestion = suggested[sourceSpace.id.rawValue]
            let matchingSpace = suggestion?.destinationID.flatMap { existing.space(id: SpaceID(rawValue: $0)) }
            return BrowserImportSpaceReview(
                sourceSpace: sourceSpace,
                destination: matchingSpace.map { .existing($0.id) } ?? .newSpace,
                customization: BrowserImportSpaceCustomization(
                    space: matchingSpace ?? sourceSpace
                ),
                includedTabIDs: suggestion.map { Set($0.includedTabIDs.map(TabID.init(rawValue:))) }
                    ?? Set(sourceSpace.tabs.map(\.id)),
                duplicateTabIDs: Set(suggestion?.duplicateTabIDs.map(TabID.init(rawValue:)) ?? []),
                placementOverrides: [:],
                spaceInclusionOverride: nil,
                passwordInclusionOverride: nil
            )
        }
    }

    /// The Spaces the import brings, in the order it brings them.
    var sources: [BrowserSpace] {
        spaces.map(\.sourceSpace)
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

    /// What the current choices mean against `browser`'s workspace, answered
    /// by the core in one pass. Empty when the core cannot answer; the import
    /// itself still enforces the pinned limit.
    @MainActor
    func analysis(in browser: BrowserStore) -> BrowserImportReviewAnalysis {
        let query = ImportReviewAnalysis(
            workspaceID: browser.family.workspaceID, sources: sources.map(ImportReviewSpace.init), reviews: reviews)
        guard let answer = try? browser.core.query(query) else { return BrowserImportReviewAnalysis() }
        var analysis = BrowserImportReviewAnalysis()
        for space in answer.spaces {
            analysis.duplicateTabIDs.formUnion(space.duplicateTabIDs.map(TabID.init(rawValue:)))
            analysis.matchedTabIDsBySourceSpace[SpaceID(rawValue: space.sourceSpaceID)] =
                Set(space.matchedTabIDs.map(TabID.init(rawValue:)))
        }
        analysis.overflowTabIDs = Set(answer.overflowTabIDs.map(TabID.init(rawValue:)))
        return analysis
    }

    /// The session the import would leave `browser`'s workspace with.
    /// Throws the rule that would refuse it.
    @MainActor
    func preview(in browser: BrowserStore) throws -> BrowserSession {
        try browser.importPreview(try intent(in: browser), of: sources)
    }

    /// The import these choices make, issued from `browser`'s window.
    @MainActor
    func intent(in browser: BrowserStore) throws -> ImportReviewedSpaces {
        ImportReviewedSpaces(
            workspaceID: browser.family.workspaceID, windowID: browser.windowID.rawValue,
            spaces: try BrowserSpace.storedFormat(sources), reviews: reviews)
    }

    /// The choices for each imported Space, each naming the Space it is for.
    private var reviews: [SpaceReview] {
        spaces.map { review in
            let destinationID: UUID? =
                switch review.destination {
                case .newSpace: nil
                case .existing(let id): id.rawValue
                }
            return SpaceReview(
                sourceSpaceID: review.id.rawValue, included: review.isIncluded, destinationID: destinationID,
                customization: review.customization.core, includedTabIDs: review.includedTabIDs.map(\.rawValue),
                placements: review.placementOverrides.map {
                    TabPlacementChoice(tabID: $0.key.rawValue, placement: $0.value)
                })
        }
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
