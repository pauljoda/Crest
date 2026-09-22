import Foundation

/// What finishing setup does, as the core decides it.
enum BrowserOnboardingCompletionOutcome: String {
    case sourceChanged
    case complete
    case openGuide
}

/// Manual-setup admission and onboarding completion rules owned by the
/// portable core. The draft stays native; the workspace import applies it.
extension BrowserCorePolicy {
    struct SetupSpace {
        let name: String
        let accent: SpaceAccent
        let symbol: String
    }

    struct SetupTab {
        let title: String
        let symbol: String
        let keepsSavedURL: Bool
    }

    /// The identity the next draft Space takes, or the limit it breaks.
    static func setupSpace(draftCount: Int) throws -> SetupSpace {
        guard let response = evaluate(["version": 1, "operation": "setup.space", "draftCount": draftCount]),
            response["error"] == nil,
            let name = response["name"] as? String, let symbol = response["symbol"] as? String,
            let accent = (response["accent"] as? String).flatMap(SpaceAccent.init(rawValue:))
        else { throw BrowserManualSetupError.spaceLimitReached }
        return SetupSpace(name: name, accent: accent, symbol: symbol)
    }

    /// How a tab presents in a draft placement, or the limit it breaks.
    /// `addedPinnedCount` counts the draft's other pinned additions.
    static func setupTab(placement: TabPlacement, existingPinnedCount: Int, addedPinnedCount: Int,
        url: URL, title: String?) throws -> SetupTab {
        let typed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let response = evaluate([
            "version": 1, "operation": "setup.tab", "placement": placement.rawValue,
            "existingPinnedCount": existingPinnedCount, "addedPinnedCount": addedPinnedCount,
            "url": url.absoluteString, "title": typed.flatMap { $0.isEmpty ? nil : $0 } as Any? ?? NSNull(),
        ]) else { throw BrowserManualSetupError.invalidAddress }
        if response["error"] as? String == "pinned_limit_reached" { throw BrowserManualSetupError.pinnedLimitReached }
        guard let resolved = response["title"] as? String, let symbol = response["symbol"] as? String,
            let keepsSavedURL = response["keepsSavedURL"] as? Bool
        else { throw BrowserManualSetupError.invalidAddress }
        return SetupTab(title: resolved, symbol: symbol, keepsSavedURL: keepsSavedURL)
    }

    /// How a draft follows Spaces changed elsewhere. Each entry names a draft
    /// to keep, an existing Space to refresh it from, or both. Nil when the
    /// core cannot answer or returns an index out of range.
    static func reconcileSetup(drafts: [(id: SpaceID, isNew: Bool)], existing: [SpaceID])
        -> [(draft: Int?, existing: Int?)]? {
        guard let response = evaluate([
            "version": 1, "operation": "setup.reconcile",
            "drafts": drafts.map { ["id": $0.id.rawValue.coreIdentifier, "isNew": $0.isNew] },
            "existing": existing.map { $0.rawValue.coreIdentifier },
        ]), let entries = response["entries"] as? [[String: Any]] else { return nil }
        var result: [(draft: Int?, existing: Int?)] = []
        for entry in entries {
            let draft = entry["draft"] as? Int, source = entry["existing"] as? Int
            guard draft != nil || source != nil,
                draft.map(drafts.indices.contains) ?? true, source.map(existing.indices.contains) ?? true
            else { return nil }
            result.append((draft, source))
        }
        return result
    }

    /// Nil when the core cannot answer; the caller treats that as a changed source.
    static func onboardingCompletion(entryPoint: BrowserOnboardingEntryPoint, hasCompletedSetup: Bool,
        isPrivateBrowsing: Bool) -> BrowserOnboardingCompletionOutcome? {
        (evaluate([
            "version": 1, "operation": "onboarding.completion", "entryPoint": entryPoint.rawValue,
            "hasCompletedSetup": hasCompletedSetup, "isPrivateBrowsing": isPrivateBrowsing,
        ])?["outcome"] as? String).flatMap(BrowserOnboardingCompletionOutcome.init(rawValue:))
    }

    /// Whether the Getting Started guide may open in `target` after its Space
    /// unlocked. An unavailable core does not open it.
    static func confirmsOnboardingGuide(target: BrowserSpaceRuntimeAssignment,
        originalFirst: BrowserSpaceRuntimeAssignment?, currentFirst: BrowserSpaceRuntimeAssignment?,
        originalTarget: BrowserSpaceRuntimeAssignment?, currentTarget: BrowserSpaceRuntimeAssignment?,
        previewFirst: BrowserSpaceRuntimeAssignment?, hasManualPlan: Bool, isLocked: Bool) -> Bool {
        func identity(_ value: BrowserSpaceRuntimeAssignment?) -> Any {
            guard let value else { return NSNull() }
            return ["spaceID": value.spaceID.rawValue.coreIdentifier, "profileID": value.profileID.coreIdentifier]
        }
        return evaluate([
            "version": 1, "operation": "onboarding.guide", "target": identity(target),
            "originalFirst": identity(originalFirst), "currentFirst": identity(currentFirst),
            "originalTarget": identity(originalTarget), "currentTarget": identity(currentTarget),
            "previewFirst": identity(previewFirst), "hasManualPlan": hasManualPlan, "locked": isLocked,
        ])?["confirmed"] as? Bool ?? false
    }
}
