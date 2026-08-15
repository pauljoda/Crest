import Foundation

extension BrowserManualSetupModel {
    func selectedDraft(
        in plan: BrowserManualSetupPlan,
        selectedSpaceID: SpaceID?
    ) -> BrowserManualSetupSpaceDraft? {
        plan.spaces.first { $0.id == selectedSpaceID }
    }

    func draft(
        _ spaceID: SpaceID,
        in plan: BrowserManualSetupPlan
    ) -> BrowserManualSetupSpaceDraft? {
        plan.spaces.first { $0.id == spaceID }
    }

    func previewSession(
        for plan: BrowserManualSetupPlan,
        mergingInto existingSession: BrowserSession
    ) -> BrowserSession? {
        try? plan.preview(mergingInto: existingSession)
    }

    func previewSpace(
        for draft: BrowserManualSetupSpaceDraft,
        in previewSession: BrowserSession?
    ) -> BrowserSpace {
        if let space = previewSession?.space(id: draft.id) {
            return space
        }
        return BrowserSpace(
            id: draft.id,
            profile: draft.profile,
            name: draft.customization.name,
            symbol: draft.customization.symbol,
            accent: draft.customization.accent,
            branding: draft.customization.branding,
            folders: [],
            tabs: draft.addedTabs,
            selectedTabID: draft.addedTabs.first?.id
        )
    }

    func addedSuggestionTab(
        _ suggestion: BrowserSetupSiteSuggestion,
        in spaceID: SpaceID,
        plan: BrowserManualSetupPlan
    ) -> BrowserTab? {
        guard let draft = draft(spaceID, in: plan) else { return nil }
        return BrowserManualSetupSitePolicy.addedSuggestionTab(
            suggestion,
            in: draft
        )
    }

    func existingContainsSuggestion(
        _ suggestion: BrowserSetupSiteSuggestion,
        in spaceID: SpaceID,
        existingSession: BrowserSession
    ) -> Bool {
        BrowserManualSetupSitePolicy.containsSuggestion(
            suggestion,
            in: existingSession.space(id: spaceID)?.tabs ?? []
        )
    }

    func manuallyAddedTabs(
        in draft: BrowserManualSetupSpaceDraft
    ) -> [BrowserTab] {
        BrowserManualSetupSitePolicy.manuallyAddedTabs(in: draft)
    }

    func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Space" : trimmed
    }
}
