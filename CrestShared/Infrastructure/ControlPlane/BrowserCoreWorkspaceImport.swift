import Foundation

/// Native draft/asset codec. Preview and commit delegate the same import intent
/// to the core; credentials and image bytes never enter the semantic command.
enum BrowserCoreWorkspaceImport {
    // MARK: - Types

    /// How the core reads an import's arguments. Raw values are the core's
    /// spellings in `WorkspaceImportMode.cs`.
    enum Mode: String, Encodable, Sendable {
        case portable
        case manual
        case review
    }

    struct Request {
        let mode: Mode
        let arguments: Arguments
        let sources: [BrowserSpace]
    }

    /// The import intent: the Spaces it brings, without image bytes, and the
    /// mode's own choices about them.
    struct Arguments: Encodable {
        let sources: [BrowserSpace]
        var drafts: [Draft]?
        var orderWasEdited: Bool?
        var reviews: [Review]?
    }

    /// One manual-setup Space, by its position in `sources`.
    struct Draft: Encodable {
        let sourceIndex: Int
        let isNew: Bool
        let customization: BrowserImportSpaceCustomization
    }

    /// One reviewed import Space, by its position in `sources`.
    struct Review: Encodable {
        let sourceIndex: Int
        let included: Bool
        @BrowserCoreNullable var destinationID: UUID?
        let customization: BrowserImportSpaceCustomization
        let includedTabIDs: [UUID]
        let placements: [PlacementOverride]
    }

    /// A tab the review moves to another placement.
    struct PlacementOverride: Encodable {
        let tabID: UUID
        let placement: TabPlacement
    }

    struct Result: Decodable {
        struct Asset: Decodable {
            /// The collection an asset's tab sits in.
            enum Section: String, Decodable {
                case tabs
                case archivedTabs
            }

            let spaceIndex: Int
            let tabIndex: Int
            @BrowserCoreOptional var section: Section?
            let sourceIndex: Int
            let sourceSpaceIndex: Int
            let sourceTabIndex: Int
        }

        let session: BrowserSession?
        let assets: [Asset]?
        let error: BrowserCoreErrorCode?

        func materialize(existing: BrowserSession, request: Request) throws -> BrowserSession {
            if let error {
                switch error {
                case .spaceLimitReached:
                    if request.mode == .manual { throw BrowserManualSetupError.spaceLimitReached }
                    throw BrowserPortableArchiveError.spaceLimitExceeded(BrowserPortableArchive.maximumSpaceCount)
                case .pinnedLimitReached: throw BrowserManualSetupError.pinnedLimitReached
                case .noIncludedSpaces: throw BrowserImportReviewPlan.ValidationError.noIncludedSpaces
                case .spaceDeletionInProgress, .wrongProfileIdentity: throw BrowserManualSetupError.missingSpace
                default: throw BrowserPortableArchiveError.invalidContents
                }
            }
            guard var result = session else { throw BrowserPortableArchiveError.invalidContents }
            for asset in assets ?? [] {
                let sourceSpaces: [BrowserSpace]
                if asset.sourceIndex == 0 {
                    sourceSpaces = existing.spaces
                } else {
                    guard request.sources.indices.contains(asset.sourceIndex - 1) else {
                        throw BrowserPortableArchiveError.invalidContents
                    }
                    sourceSpaces = [request.sources[asset.sourceIndex - 1]]
                }
                guard sourceSpaces.indices.contains(asset.sourceSpaceIndex),
                    result.spaces.indices.contains(asset.spaceIndex)
                else { throw BrowserPortableArchiveError.invalidContents }
                let source = sourceSpaces[asset.sourceSpaceIndex]
                switch asset.section {
                case .tabs:
                    guard source.tabs.indices.contains(asset.sourceTabIndex),
                        result.spaces[asset.spaceIndex].tabs.indices.contains(asset.tabIndex)
                    else { throw BrowserPortableArchiveError.invalidContents }
                    result.spaces[asset.spaceIndex].tabs[asset.tabIndex].faviconData =
                        source.tabs[asset.sourceTabIndex].faviconData
                case .archivedTabs:
                    guard source.archivedTabs.indices.contains(asset.sourceTabIndex),
                        result.spaces[asset.spaceIndex].archivedTabs.indices.contains(asset.tabIndex)
                    else { throw BrowserPortableArchiveError.invalidContents }
                    result.spaces[asset.spaceIndex].archivedTabs[asset.tabIndex].tab.faviconData =
                        source.archivedTabs[asset.sourceTabIndex].tab.faviconData
                case nil:
                    throw BrowserPortableArchiveError.invalidContents
                }
            }
            return result
        }
    }

    private struct PreviewRequest: Encodable {
        let mode: Mode
        let session: BrowserSession
        let arguments: Arguments
        let now: TimeInterval
    }

    // MARK: - Actions - Requests

    static func portable(_ spaces: [BrowserSpace]) throws -> Request {
        Request(mode: .portable, arguments: Arguments(sources: compact(spaces)), sources: spaces)
    }

    static func manual(_ plan: BrowserManualSetupPlan) throws -> Request {
        let sources = plan.spaces.map { draft in
            BrowserSpace(
                id: draft.id, profile: draft.profile, name: draft.customization.name,
                symbol: draft.customization.symbol, accent: draft.customization.accent,
                branding: draft.customization.branding, folders: [], tabs: draft.addedTabs)
        }
        let drafts = plan.spaces.enumerated().map { index, draft in
            Draft(sourceIndex: index, isNew: draft.isNew, customization: customization(draft.customization))
        }
        return Request(
            mode: .manual,
            arguments: Arguments(
                sources: compact(sources), drafts: drafts, orderWasEdited: plan.coreSpaceOrderWasEdited),
            sources: sources)
    }

    static func review(_ plan: BrowserImportReviewPlan) throws -> Request {
        let sources = plan.spaces.map(\.sourceSpace)
        let reviews = plan.spaces.enumerated().map { index, review in
            Review(
                sourceIndex: index, included: review.isIncluded, destinationID: destinationID(review.destination),
                customization: customization(review.customization),
                includedTabIDs: review.includedTabIDs.map(\.rawValue),
                placements: placements(review.placementOverrides))
        }
        return Request(
            mode: .review, arguments: Arguments(sources: compact(sources), reviews: reviews), sources: sources)
    }

    static func preview(_ request: Request, existing: BrowserSession) throws -> BrowserSession {
        let result: Result = try BrowserCoreSync.query(
            .workspacePreview,
            PreviewRequest(
                mode: request.mode, session: BrowserCoreSessionAuthority.compact(existing),
                arguments: request.arguments, now: Date.now.timeIntervalSinceReferenceDate))
        return try result.materialize(existing: existing, request: request)
    }

    private static func customization(_ source: BrowserImportSpaceCustomization) -> BrowserImportSpaceCustomization {
        var value = source
        // Normalize the native rendering vocabulary, not the import decision.
        value.branding = value.branding.normalized()
        return value
    }

    private static func compact(_ spaces: [BrowserSpace]) -> [BrowserSpace] {
        guard !spaces.isEmpty else { return [] }
        return BrowserCoreSessionAuthority.compact(BrowserSession(spaces: spaces)).spaces
    }

    fileprivate static func destinationID(_ destination: BrowserImportDestination) -> UUID? {
        switch destination {
        case .newSpace: nil
        case .existing(let id): id.rawValue
        }
    }

    fileprivate static func placements(_ overrides: [TabID: TabPlacement]) -> [PlacementOverride] {
        overrides.map { PlacementOverride(tabID: $0.key.rawValue, placement: $0.value) }
    }
}

/// Import review rules owned by the core. They read whole Spaces (identities,
/// names, addresses and placements; never images), so they run on the
/// workspace query path beside the preview they prepare.
extension BrowserCoreWorkspaceImport {
    // MARK: - Types

    struct ReviewSuggestion {
        let destinationID: SpaceID?
        let duplicateTabIDs: Set<TabID>
        let includedTabIDs: Set<TabID>
    }

    /// A Space as the review rules read it.
    private struct ReviewSpace: Encodable {
        struct Tab: Encodable {
            let id: UUID
            @BrowserCoreNullable var url: String?
            let placement: TabPlacement
        }

        let id: UUID
        let name: String
        let tabs: [Tab]

        init(_ space: BrowserSpace) {
            id = space.id.rawValue
            name = space.name
            tabs = space.tabs.map { Tab(id: $0.id.rawValue, url: $0.url?.absoluteString, placement: $0.placement) }
        }
    }

    /// The person's current choice for one imported Space.
    private struct ReviewChoice: Encodable {
        let included: Bool
        @BrowserCoreNullable var destinationID: UUID?
        let includedTabIDs: [UUID]
        let placements: [PlacementOverride]
    }

    private struct ReviewRequest: Encodable {
        var replacesDisposableSeed: Bool?
        let existing: [ReviewSpace]
        let sources: [ReviewSpace]
        /// Null asks for starting suggestions; choices ask for their analysis.
        @BrowserCoreNullable var choices: [ReviewChoice]?
    }

    private struct ReviewSuggestions: Decodable {
        struct Suggestion: Decodable {
            let destinationID: UUID?
            let duplicateTabIDs: [UUID]
            let includedTabIDs: [UUID]
        }

        let suggestions: [Suggestion]
    }

    private struct ReviewAnalysis: Decodable {
        let duplicateTabIDs: [[UUID]]
        let matchedTabIDs: [[UUID]]
        let overflowTabIDs: [UUID]
    }

    // MARK: - Actions - Review

    /// The starting review for each imported Space, in order. Nil when the
    /// core cannot answer.
    static func reviewSuggestions(sources: [BrowserSpace], existing: BrowserSession) -> [ReviewSuggestion]? {
        let request = ReviewRequest(
            replacesDisposableSeed: existing.hasDisposableSeedState, existing: existing.spaces.map(ReviewSpace.init),
            sources: sources.map(ReviewSpace.init), choices: nil)
        guard let result: ReviewSuggestions = try? BrowserCoreSync.query(.workspaceReview, request),
            result.suggestions.count == sources.count
        else { return nil }
        return result.suggestions.map {
            ReviewSuggestion(
                destinationID: $0.destinationID.map(SpaceID.init(rawValue:)),
                duplicateTabIDs: Set($0.duplicateTabIDs.map(TabID.init(rawValue:))),
                includedTabIDs: Set($0.includedTabIDs.map(TabID.init(rawValue:))))
        }
    }

    /// What the plan's current choices mean against `existing`. Nil when the
    /// core cannot answer.
    static func reviewAnalysis(_ plan: BrowserImportReviewPlan, existing: BrowserSession)
        -> BrowserImportReviewAnalysis?
    {
        let choices = plan.spaces.map { review in
            ReviewChoice(
                included: review.isIncluded, destinationID: destinationID(review.destination),
                includedTabIDs: review.includedTabIDs.map(\.rawValue), placements: placements(review.placementOverrides)
            )
        }
        let request = ReviewRequest(
            existing: existing.spaces.map(ReviewSpace.init), sources: plan.spaces.map { ReviewSpace($0.sourceSpace) },
            choices: choices)
        guard let result: ReviewAnalysis = try? BrowserCoreSync.query(.workspaceReview, request),
            result.duplicateTabIDs.count == plan.spaces.count, result.matchedTabIDs.count == plan.spaces.count
        else { return nil }
        var analysis = BrowserImportReviewAnalysis()
        for (index, review) in plan.spaces.enumerated() {
            analysis.duplicateTabIDs.formUnion(result.duplicateTabIDs[index].map(TabID.init(rawValue:)))
            analysis.matchedTabIDsBySourceSpace[review.id] = Set(result.matchedTabIDs[index].map(TabID.init(rawValue:)))
        }
        analysis.overflowTabIDs = Set(result.overflowTabIDs.map(TabID.init(rawValue:)))
        return analysis
    }
}
