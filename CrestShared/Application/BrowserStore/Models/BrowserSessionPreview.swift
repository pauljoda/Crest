import Foundation

/// A session no workspace holds, as the previews draw it: its Spaces as the
/// read model would hold them, and the images their tabs would wear. Nothing
/// the core publishes ever reaches it.
@MainActor
struct BrowserSessionPreview {
    // MARK: - Variables

    let spaces: [SpaceModel]
    let favicons: FaviconAssets
    /// The session as the core gave it, before anything the preview wears.
    let session: SessionState
    /// The image each tab wears, by tab.
    let images: [UUID: Data]

    // MARK: - Initializers

    /// The session an import would leave: each tab it keeps wears the image
    /// `images` holds for it, or for the tab it was copied from, and each tab
    /// it brings wears none until the import takes it.
    init(importing preview: ImportedWorkspace, images: FaviconAssets) {
        let copies = Dictionary(preview.copied.map { ($0.copyTabID, $0.sourceTabID) }) { first, _ in first }
        let imported = Set(preview.imported.map(\.tabID))
        var kept: [UUID: Data] = [:]
        for space in preview.session.spaces {
            for tab in space.tabs where !imported.contains(tab.id) {
                kept[tab.id] = images.image(of: copies[tab.id] ?? tab.id)
            }
        }
        spaces = preview.session.spaces.map(SpaceModel.init)
        favicons = FaviconAssets()
        favicons.adopt(kept, holding: { _ in true })
        session = preview.session
        self.images = kept
    }

    // MARK: - Actions - Reading

    /// The Space the session holds with this identity.
    func space(id: UUID) -> SpaceModel? {
        spaces.first { $0.id == id }
    }
}

// MARK: - Setup

extension BrowserSessionPreview {
    /// The session as a new window of Crest would open over it, with each
    /// Space the manual setup `draft` holds wearing the name, icon and look
    /// the setup gave it.
    func seed(wearing draft: SetupDraft?) -> SessionState.Seed {
        var seed = session.seed
        for entry in draft?.spaces ?? [] {
            guard let index = seed.spaces.firstIndex(where: { $0.id == entry.spaceID }) else { continue }
            let customization = entry.customization
            seed.spaces[index] = seed.spaces[index].wearing(
                customization.branding, symbol: customization.symbol, name: customization.name)
        }
        return seed
    }

    /// The preview with each Space the manual setup `draft` holds wearing the
    /// name, icon and look the setup gave it, as finishing setup would apply
    /// them.
    func wearing(_ draft: SetupDraft?) -> BrowserSessionPreview {
        guard let draft else { return self }
        for entry in draft.spaces {
            guard let space = space(id: entry.spaceID) else { continue }
            space.settings.update(space.settings.value.wearing(entry.customization))
        }
        return self
    }
}

extension SpaceSettings {
    /// These settings with `customization`'s name, symbol, accent and look.
    fileprivate func wearing(_ customization: SpaceCustomization) -> SpaceSettings {
        SpaceSettings(
            name: customization.name, symbol: customization.symbol, accent: customization.accent,
            branding: customization.branding, browsingPreferences: browsingPreferences,
            credentialPreferences: credentialPreferences, accessPolicy: accessPolicy,
            isSavedTabsExpanded: isSavedTabsExpanded, savedTabsExpansionModifiedAt: savedTabsExpansionModifiedAt,
            credentialsEnabledModifiedAt: credentialsEnabledModifiedAt, accessPolicyModifiedAt: accessPolicyModifiedAt,
            separatesPinnedTabs: separatesPinnedTabs, separatesPinnedTabsModifiedAt: separatesPinnedTabsModifiedAt,
            protectionModifiedAt: protectionModifiedAt, look: customization.branding,
            requiresAuthentication: requiresAuthentication)
    }
}
