@MainActor
enum MobileOnboardingSpacePreviewFactory {
    /// `draft`'s Space as `previewSession`, the session the setup would leave,
    /// holds it, or as the draft describes it when the core would refuse the
    /// setup.
    static func preview(
        draft: BrowserManualSetupSpaceDraft,
        previewSession: BrowserSession?,
        includesSamples: Bool
    ) -> BrowserSpace {
        var space = resolvedSpace(draft: draft, previewSession: previewSession)
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
                tabs.firstIndex { !$0.placement.isDurable }
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
        previewSession: BrowserSession?
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
            tabs: []
        )
    }
}
