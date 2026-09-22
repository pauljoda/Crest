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
                branding: draft.customization.branding, folders: [], tabs: draft.addedTabs, selectedTabID: nil)
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
        guard let first = spaces.first else { return [] as [Any] }
        return try BrowserCoreSync.value(BrowserCoreSessionAuthority.compact(
            BrowserSession(spaces: spaces, selectedSpaceID: first.id)).spaces)
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
