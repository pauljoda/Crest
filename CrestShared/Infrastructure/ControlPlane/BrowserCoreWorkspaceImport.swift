import Foundation

/// Native draft/asset codec. Preview and commit delegate the same import intent
/// to the core; credentials and image bytes never enter the semantic command.
enum BrowserCoreWorkspaceImport {
    struct Request {
        let mode: String
        let arguments: [String: Any]
        let sources: [BrowserSpace]
    }

    static func portable(_ spaces: [BrowserSpace]) throws -> Request {
        Request(mode: "portable", arguments: ["sources": try compact(spaces)], sources: spaces)
    }

    static func manual(_ plan: BrowserManualSetupPlan) throws -> Request {
        let sources = plan.spaces.map { draft in
            BrowserSpace(id: draft.id, profile: draft.profile, name: draft.customization.name,
                symbol: draft.customization.symbol, accent: draft.customization.accent,
                branding: draft.customization.branding, folders: [], tabs: draft.addedTabs)
        }
        let drafts = try plan.spaces.enumerated().map { index, draft -> [String: Any] in
            ["sourceIndex": index, "isNew": draft.isNew, "customization": try customization(draft.customization)]
        }
        return Request(mode: "manual", arguments: ["sources": try compact(sources), "drafts": drafts,
            "orderWasEdited": plan.coreSpaceOrderWasEdited], sources: sources)
    }

    static func review(_ plan: BrowserImportReviewPlan) throws -> Request {
        let sources = plan.spaces.map(\.sourceSpace)
        let reviews = try plan.spaces.enumerated().map { index, review -> [String: Any] in
            let destination: Any
            switch review.destination {
            case .newSpace: destination = NSNull()
            case .existing(let id): destination = id.rawValue.uuidString
            }
            return ["sourceIndex": index, "included": review.isIncluded, "destinationID": destination,
                "customization": try customization(review.customization),
                "includedTabIDs": review.includedTabIDs.map { $0.rawValue.uuidString },
                "placements": review.placementOverrides.map { ["tabID": $0.key.rawValue.uuidString, "placement": $0.value.rawValue] }]
        }
        return Request(mode: "review", arguments: ["sources": try compact(sources), "reviews": reviews], sources: sources)
    }

    private static func customization(_ source: BrowserImportSpaceCustomization) throws -> Any {
        var value = source
        // Normalize the native rendering vocabulary, not the import decision.
        value.branding = value.branding.normalized()
        return try BrowserCoreSync.value(value)
    }
    private static func compact(_ spaces: [BrowserSpace]) throws -> Any {
        guard !spaces.isEmpty else { return [] as [Any] }
        return try BrowserCoreSync.value(BrowserCoreSessionAuthority.compact(BrowserSession(spaces: spaces)).spaces)
    }

    static func preview(_ request: Request, existing: BrowserSession) throws -> BrowserSession {
        let result: Result = try BrowserCoreSync.query([
            "version": 1, "operation": "workspace.preview", "mode": request.mode,
            "session": try BrowserCoreSync.value(BrowserCoreSessionAuthority.compact(existing)),
            "arguments": request.arguments, "now": Date.now.timeIntervalSinceReferenceDate
        ])
        return try result.materialize(existing: existing, request: request)
    }

    struct Result: Decodable {
        let session: BrowserSession?
        let assets: [Asset]?
        let error: String?
        /// The imported Space and the tabs it shows first, for the importing window.
        let selection: BrowserSelectionHint?
        struct Asset: Decodable {
            let spaceIndex: Int
            let tabIndex: Int
            let section: String
            let sourceIndex: Int
            let sourceSpaceIndex: Int
            let sourceTabIndex: Int
        }
        func materialize(existing: BrowserSession, request: Request) throws -> BrowserSession {
            if let error {
                switch error {
                case "space_limit_reached":
                    if request.mode == "manual" { throw BrowserManualSetupError.spaceLimitReached }
                    throw BrowserPortableArchiveError.spaceLimitExceeded(BrowserPortableArchive.maximumSpaceCount)
                case "pinned_limit_reached": throw BrowserManualSetupError.pinnedLimitReached
                case "no_included_spaces": throw BrowserImportReviewPlan.ValidationError.noIncludedSpaces
                case "space_deletion_in_progress", "wrong_profile_identity": throw BrowserManualSetupError.missingSpace
                default: throw BrowserPortableArchiveError.invalidContents
                }
            }
            guard var result = session else { throw BrowserPortableArchiveError.invalidContents }
            for asset in assets ?? [] {
                let sourceSpaces: [BrowserSpace]
                if asset.sourceIndex == 0 { sourceSpaces = existing.spaces }
                else {
                    guard request.sources.indices.contains(asset.sourceIndex - 1) else { throw BrowserPortableArchiveError.invalidContents }
                    sourceSpaces = [request.sources[asset.sourceIndex - 1]]
                }
                guard sourceSpaces.indices.contains(asset.sourceSpaceIndex), result.spaces.indices.contains(asset.spaceIndex)
                else { throw BrowserPortableArchiveError.invalidContents }
                let source = sourceSpaces[asset.sourceSpaceIndex]
                if asset.section == "tabs" {
                    guard source.tabs.indices.contains(asset.sourceTabIndex), result.spaces[asset.spaceIndex].tabs.indices.contains(asset.tabIndex)
                    else { throw BrowserPortableArchiveError.invalidContents }
                    result.spaces[asset.spaceIndex].tabs[asset.tabIndex].faviconData = source.tabs[asset.sourceTabIndex].faviconData
                } else if asset.section == "archivedTabs" {
                    guard source.archivedTabs.indices.contains(asset.sourceTabIndex), result.spaces[asset.spaceIndex].archivedTabs.indices.contains(asset.tabIndex)
                    else { throw BrowserPortableArchiveError.invalidContents }
                    result.spaces[asset.spaceIndex].archivedTabs[asset.tabIndex].tab.faviconData = source.archivedTabs[asset.sourceTabIndex].tab.faviconData
                } else { throw BrowserPortableArchiveError.invalidContents }
            }
            return result
        }
    }
}

/// Import review rules owned by the core. They read whole Spaces (identities,
/// names, addresses and placements; never images), so they run on the
/// workspace query path beside the preview they prepare.
extension BrowserCoreWorkspaceImport {
    struct ReviewSuggestion {
        let destinationID: SpaceID?
        let duplicateTabIDs: Set<TabID>
        let includedTabIDs: Set<TabID>
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

    private static func reviewSpaces(_ spaces: [BrowserSpace]) -> [[String: Any]] {
        spaces.map { space in
            ["id": space.id.rawValue.uuidString, "name": space.name, "tabs": space.tabs.map { tab in
                ["id": tab.id.rawValue.uuidString, "url": tab.url?.absoluteString as Any? ?? NSNull(),
                 "placement": tab.placement.rawValue] as [String: Any]
            }]
        }
    }

    /// The starting review for each imported Space, in order. Nil when the
    /// core cannot answer.
    static func reviewSuggestions(sources: [BrowserSpace], existing: BrowserSession) -> [ReviewSuggestion]? {
        guard let result: ReviewSuggestions = try? BrowserCoreSync.query([
            "version": 1, "operation": "workspace.review", "replacesDisposableSeed": existing.hasDisposableSeedState,
            "existing": reviewSpaces(existing.spaces), "sources": reviewSpaces(sources), "choices": NSNull(),
        ]), result.suggestions.count == sources.count else { return nil }
        return result.suggestions.map {
            ReviewSuggestion(destinationID: $0.destinationID.map(SpaceID.init(rawValue:)),
                duplicateTabIDs: Set($0.duplicateTabIDs.map(TabID.init(rawValue:))),
                includedTabIDs: Set($0.includedTabIDs.map(TabID.init(rawValue:))))
        }
    }

    /// What the plan's current choices mean against `existing`. Nil when the
    /// core cannot answer.
    static func reviewAnalysis(_ plan: BrowserImportReviewPlan, existing: BrowserSession) -> BrowserImportReviewAnalysis? {
        let choices = plan.spaces.map { review -> [String: Any] in
            let destination: Any
            switch review.destination {
            case .newSpace: destination = NSNull()
            case .existing(let id): destination = id.rawValue.uuidString
            }
            return ["included": review.isIncluded, "destinationID": destination,
                "includedTabIDs": review.includedTabIDs.map { $0.rawValue.uuidString },
                "placements": review.placementOverrides.map { ["tabID": $0.key.rawValue.uuidString, "placement": $0.value.rawValue] }]
        }
        guard let result: ReviewAnalysis = try? BrowserCoreSync.query([
            "version": 1, "operation": "workspace.review", "existing": reviewSpaces(existing.spaces),
            "sources": reviewSpaces(plan.spaces.map(\.sourceSpace)), "choices": choices,
        ]), result.duplicateTabIDs.count == plan.spaces.count, result.matchedTabIDs.count == plan.spaces.count
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
