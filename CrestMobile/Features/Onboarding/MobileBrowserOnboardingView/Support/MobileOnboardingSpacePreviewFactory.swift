enum MobileOnboardingSpacePreviewFactory {
    static func preview(
        draft: BrowserManualSetupSpaceDraft,
        plan: BrowserManualSetupPlan,
        existingSession: BrowserSession,
        includesSamples: Bool
    ) -> BrowserSpace {
        var space = resolvedSpace(
            draft: draft,
            plan: plan,
            existingSession: existingSession
        )
        guard includesSamples else { return space }

        var tabs = space.tabs
        if space.pinnedTabs.isEmpty {
            tabs.insert(
                contentsOf: MobileOnboardingPreviewFixtures.samplePinnedTabs,
                at: 0
            )
        }
        if space.savedTabs.isEmpty {
            let savedIndex =
                tabs.firstIndex { $0.placement == .current }
                ?? tabs.endIndex
            tabs.insert(
                contentsOf: MobileOnboardingPreviewFixtures.sampleSavedTabs,
                at: savedIndex
            )
        }
        space.tabs = tabs
        return space
    }

    private static func resolvedSpace(
        draft: BrowserManualSetupSpaceDraft,
        plan: BrowserManualSetupPlan,
        existingSession: BrowserSession
    ) -> BrowserSpace {
        if let preview = try? plan.preview(mergingInto: existingSession),
            let space = preview.space(id: draft.id)
        {
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
            tabs: [],
            selectedTabID: nil
        )
    }
}
