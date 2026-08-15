import SwiftUI

/// The bindings a settings pane needs to edit one Space, written once.
///
/// Eight panes across the two shells had each grown a private copy of the same four
/// accessors — repair the Space selection, read-through-and-write-back a field of the
/// Space, of its browsing preferences, of its credential preferences — and the copies
/// had already begun to drift: some read the live Space out of the session before
/// writing, some wrote back a stale capture. Every copy here reads the live Space
/// first and falls back to the view's captured value only when the Space has just
/// been deleted out from under it, which is the behaviour the shells agreed on when
/// they agreed at all.
extension BrowserStore {
    /// The Space a pane should be showing, given what it is showing now.
    ///
    /// A pane holds its own `SpaceID?` because "no Space yet" is a real state while a
    /// pane is appearing. This answers the only question a pane asks about it: is
    /// that still a Space, and if not, which one now?
    func repairedSpaceSelection(_ selection: SpaceID?) -> SpaceID? {
        guard let selection, session.space(id: selection) != nil else {
            return session.selectedSpaceID
        }
        return selection
    }

    /// The live Space behind a view's captured copy.
    ///
    /// A `ForEach`/`if let` hands a view a *value*, and the value goes stale the
    /// moment anything edits it. Every binding below resolves through here so an
    /// edit is always applied to what the session holds now.
    func liveSpace(_ space: BrowserSpace) -> BrowserSpace {
        session.space(id: space.id) ?? space
    }

    /// One field of a Space's identity. Writing routes through
    /// `updateSpaceIdentity`, which is the only door into a Space's name, symbol,
    /// and accent.
    func spaceIdentityBinding<Value>(
        _ keyPath: WritableKeyPath<BrowserSpace, Value>,
        in space: BrowserSpace
    ) -> Binding<Value> {
        Binding { [self] in
            liveSpace(space)[keyPath: keyPath]
        } set: { [self] value in
            var identity = liveSpace(space)
            identity[keyPath: keyPath] = value
            updateSpaceIdentity(
                space.id,
                name: identity.name,
                symbol: identity.symbol,
                accent: identity.accent
            )
        }
    }

    /// One field of a Space's browsing preferences — its search provider, its
    /// current-tab cleanup policy, its content-blocking policy.
    func browsingPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<BrowserSpaceBrowsingPreferences, Value>,
        in space: BrowserSpace
    ) -> Binding<Value> {
        Binding { [self] in
            liveSpace(space).browsingPreferences[keyPath: keyPath]
        } set: { [self] value in
            var preferences = liveSpace(space).browsingPreferences
            preferences[keyPath: keyPath] = value
            updateBrowsingPreferences(preferences, in: space.id)
        }
    }

    /// The same, addressed by identifier, for panes whose Space selection is an
    /// optional they resolve per read — Privacy asks for a policy before it is sure
    /// it has a Space.
    func browsingPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<BrowserSpaceBrowsingPreferences, Value>,
        in spaceID: SpaceID?,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding { [self] in
            guard let spaceID,
                let space = session.space(id: spaceID)
            else { return defaultValue }
            return space.browsingPreferences[keyPath: keyPath]
        } set: { [self] value in
            guard let spaceID,
                var preferences = session.space(id: spaceID)?
                    .browsingPreferences
            else { return }
            preferences[keyPath: keyPath] = value
            updateBrowsingPreferences(preferences, in: spaceID)
        }
    }

    /// One field of a Space's credential preferences. Synchronization is *not*
    /// written through here: turning iCloud Keychain on or off rewrites existing
    /// items and can fail, so it goes through ``BrowserCredentialSpaceStore``.
    func credentialPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<BrowserCredentialPreferences, Value>,
        in space: BrowserSpace
    ) -> Binding<Value> {
        Binding { [self] in
            liveSpace(space).credentialPreferences[keyPath: keyPath]
        } set: { [self] value in
            var preferences = liveSpace(space).credentialPreferences
            preferences[keyPath: keyPath] = value
            updateCredentialPreferences(preferences, in: space.id)
        }
    }

    /// A Space's branding, which is edited as a whole value rather than field by
    /// field because the branding editor composes it.
    func spaceBrandingBinding(in space: BrowserSpace) -> Binding<BrowserSpaceBranding> {
        Binding { [self] in
            liveSpace(space).branding
        } set: { [self] branding in
            updateSpaceBranding(branding, in: space.id)
        }
    }

    /// The Space a pane defaults to, for preferences that always resolve to one.
    func defaultSpaceBinding() -> Binding<SpaceID> {
        Binding { [self] in
            session.defaultSpaceID ?? session.selectedSpaceID
        } set: { [self] spaceID in
            setDefaultSpace(spaceID)
        }
    }
}
