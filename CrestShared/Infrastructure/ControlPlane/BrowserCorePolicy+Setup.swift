import Foundation

/// What finishing setup does, as the core decides it.
enum BrowserOnboardingCompletionOutcome: String, Decodable {
    case sourceChanged
    case complete
    case openGuide
}

/// Manual-setup admission and onboarding completion rules owned by the
/// portable core. The draft stays native; the workspace import applies it.
extension BrowserCorePolicy {
    // MARK: - Types

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

    private struct SetupSpaceRequest: Encodable {
        let draftCount: Int
    }

    private struct SetupSpaceAnswer: Decodable {
        @BrowserCoreOptional var error: BrowserCoreErrorCode?
        @BrowserCoreOptional var name: String?
        @BrowserCoreOptional var symbol: String?
        @BrowserCoreOptional var accent: SpaceAccent?
    }

    private struct SetupTabRequest: Encodable {
        let placement: TabPlacement
        let existingPinnedCount: Int
        let addedPinnedCount: Int
        let url: String
        @BrowserCoreNullable var title: String?
    }

    private struct SetupTabAnswer: Decodable {
        @BrowserCoreOptional var error: BrowserCoreErrorCode?
        @BrowserCoreOptional var title: String?
        @BrowserCoreOptional var symbol: String?
        @BrowserCoreOptional var keepsSavedURL: Bool?
    }

    private struct ReconcileRequest: Encodable {
        struct Draft: Encodable {
            let id: String
            let isNew: Bool
        }

        let drafts: [Draft]
        let existing: [String]
    }

    private struct ReconcileAnswer: Decodable {
        struct Entry: Decodable {
            @BrowserCoreOptional var draft: Int?
            @BrowserCoreOptional var existing: Int?
        }

        let entries: [Entry]
    }

    private struct CompletionRequest: Encodable {
        let entryPoint: BrowserOnboardingEntryPoint
        let hasCompletedSetup: Bool
        let isPrivateBrowsing: Bool
    }

    private struct CompletionAnswer: Decodable {
        @BrowserCoreOptional var outcome: BrowserOnboardingCompletionOutcome?
    }

    private struct GuideRequest: Encodable {
        /// One Space identity in the core's spelling.
        struct Identity: Encodable {
            let spaceID: String
            let profileID: String

            init(_ assignment: BrowserSpaceRuntimeAssignment) {
                spaceID = assignment.spaceID.rawValue.coreIdentifier
                profileID = assignment.profileID.coreIdentifier
            }
        }

        let target: Identity
        @BrowserCoreNullable var originalFirst: Identity?
        @BrowserCoreNullable var currentFirst: Identity?
        @BrowserCoreNullable var originalTarget: Identity?
        @BrowserCoreNullable var currentTarget: Identity?
        @BrowserCoreNullable var previewFirst: Identity?
        let hasManualPlan: Bool
        let locked: Bool
    }

    private struct GuideAnswer: Decodable {
        @BrowserCoreOptional var confirmed: Bool?
    }

    // MARK: - Actions - Setup

    /// The identity the next draft Space takes, or the limit it breaks.
    static func setupSpace(draftCount: Int) throws -> SetupSpace {
        guard
            let answer = evaluate(
                .setupSpace, SetupSpaceRequest(draftCount: draftCount), answer: SetupSpaceAnswer.self),
            answer.error == nil,
            let name = answer.name, let symbol = answer.symbol, let accent = answer.accent
        else { throw BrowserManualSetupError.spaceLimitReached }
        return SetupSpace(name: name, accent: accent, symbol: symbol)
    }

    /// How a tab presents in a draft placement, or the limit it breaks.
    /// `addedPinnedCount` counts the draft's other pinned additions.
    static func setupTab(
        placement: TabPlacement, existingPinnedCount: Int, addedPinnedCount: Int,
        url: URL, title: String?
    ) throws -> SetupTab {
        let typed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SetupTabRequest(
            placement: placement, existingPinnedCount: existingPinnedCount, addedPinnedCount: addedPinnedCount,
            url: url.absoluteString, title: typed.flatMap { $0.isEmpty ? nil : $0 })
        guard let answer = evaluate(.setupTab, request, answer: SetupTabAnswer.self) else {
            throw BrowserManualSetupError.invalidAddress
        }
        if answer.error == .pinnedLimitReached { throw BrowserManualSetupError.pinnedLimitReached }
        guard let resolved = answer.title, let symbol = answer.symbol, let keepsSavedURL = answer.keepsSavedURL
        else { throw BrowserManualSetupError.invalidAddress }
        return SetupTab(title: resolved, symbol: symbol, keepsSavedURL: keepsSavedURL)
    }

    /// How a draft follows Spaces changed elsewhere. Each entry names a draft
    /// to keep, an existing Space to refresh it from, or both. Nil when the
    /// core cannot answer or returns an index out of range.
    static func reconcileSetup(drafts: [(id: SpaceID, isNew: Bool)], existing: [SpaceID])
        -> [(draft: Int?, existing: Int?)]?
    {
        let request = ReconcileRequest(
            drafts: drafts.map { ReconcileRequest.Draft(id: $0.id.rawValue.coreIdentifier, isNew: $0.isNew) },
            existing: existing.map { $0.rawValue.coreIdentifier })
        guard let answer = evaluate(.setupReconcile, request, answer: ReconcileAnswer.self) else { return nil }
        var result: [(draft: Int?, existing: Int?)] = []
        for entry in answer.entries {
            let draft = entry.draft
            let source = entry.existing
            guard draft != nil || source != nil,
                draft.map(drafts.indices.contains) ?? true, source.map(existing.indices.contains) ?? true
            else { return nil }
            result.append((draft, source))
        }
        return result
    }

    /// Nil when the core cannot answer; the caller treats that as a changed source.
    static func onboardingCompletion(
        entryPoint: BrowserOnboardingEntryPoint, hasCompletedSetup: Bool,
        isPrivateBrowsing: Bool
    ) -> BrowserOnboardingCompletionOutcome? {
        let request = CompletionRequest(
            entryPoint: entryPoint, hasCompletedSetup: hasCompletedSetup, isPrivateBrowsing: isPrivateBrowsing)
        return evaluate(.onboardingCompletion, request, answer: CompletionAnswer.self)?.outcome
    }

    /// Whether the Getting Started guide may open in `target` after its Space
    /// unlocked. An unavailable core does not open it.
    static func confirmsOnboardingGuide(
        target: BrowserSpaceRuntimeAssignment,
        originalFirst: BrowserSpaceRuntimeAssignment?, currentFirst: BrowserSpaceRuntimeAssignment?,
        originalTarget: BrowserSpaceRuntimeAssignment?, currentTarget: BrowserSpaceRuntimeAssignment?,
        previewFirst: BrowserSpaceRuntimeAssignment?, hasManualPlan: Bool, isLocked: Bool
    ) -> Bool {
        let request = GuideRequest(
            target: GuideRequest.Identity(target),
            originalFirst: originalFirst.map(GuideRequest.Identity.init),
            currentFirst: currentFirst.map(GuideRequest.Identity.init),
            originalTarget: originalTarget.map(GuideRequest.Identity.init),
            currentTarget: currentTarget.map(GuideRequest.Identity.init),
            previewFirst: previewFirst.map(GuideRequest.Identity.init),
            hasManualPlan: hasManualPlan, locked: isLocked)
        return evaluate(.onboardingGuide, request, answer: GuideAnswer.self)?.confirmed ?? false
    }
}
