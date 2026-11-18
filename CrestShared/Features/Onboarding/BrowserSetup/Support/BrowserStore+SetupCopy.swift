import Foundation

extension SessionState.Seed {
    /// The Spaces, folders and tabs the seed holds, in order, which a copy of
    /// it can only take by opening again. A blank Start Page, which each
    /// preview of a new Space opens under a new identity, is left out.
    var setupOutline: [[UUID]] {
        spaces.map { space in
            [space.id] + space.folders.map(\.id)
                + space.tabs.filter { $0.url != nil || $0.nativeContent != nil || $0.savedURL != nil }.map(\.id)
        }
    }
}

/// A store over a memory-only copy of the session setup would leave, which
/// setup's preview shows and keeps up with each change.
extension BrowserStore {
    // MARK: - Actions - Copying

    /// Gives each Space of the copy the name, icon and look `new` gives it
    /// where they differ from `old`'s, as Crest applies them.
    func wearSetup(_ new: SessionState.Seed, over old: SessionState.Seed) {
        for (was, now) in zip(old.spaces, new.spaces) where was.settings != now.settings {
            let settings = now.settings
            if settings.name != was.settings.name || settings.symbol != was.settings.symbol
                || settings.accent != was.settings.accent
            {
                _ = try? core.send(
                    SetSpaceIdentity(
                        workspaceID: family.workspaceID, spaceID: now.id, name: settings.name,
                        symbol: settings.symbol, accent: settings.accent))
            }
            if let branding = settings.branding, branding != was.settings.branding {
                _ = try? core.send(
                    SetSpaceBranding(workspaceID: family.workspaceID, spaceID: now.id, branding: branding))
            }
        }
    }

    /// Dresses Space `spaceID` in `look` for a moment, as setup's welcome
    /// shows what Crest can look like.
    func wearLook(_ look: SpaceBranding, on spaceID: UUID) {
        _ = try? core.send(SetSpaceBranding(workspaceID: family.workspaceID, spaceID: spaceID, branding: look))
    }

    /// Gives every Space of the copy the look `seed` gives it, putting back
    /// any look the welcome dressed it in.
    func wearLooks(of seed: SessionState.Seed) {
        for space in seed.spaces {
            guard let branding = space.settings.branding else { continue }
            _ = try? core.send(
                SetSpaceBranding(workspaceID: family.workspaceID, spaceID: space.id, branding: branding))
        }
    }

    /// Shows Space `spaceID` on a Start Page, as Crest enters a Space whose
    /// pages are not loaded, so no page in the copy loads.
    func showSetupSpace(_ spaceID: UUID) {
        guard window.shownSpaceID != spaceID else { return }
        _ = try? core.send(ShowSpace(windowID: windowID, spaceID: spaceID))
        presentStartPageForSpaceEntry()
    }
}
