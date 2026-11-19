import SwiftUI

/// The browser setup builds on iPhone and iPad, as Crest itself runs it: a
/// memory-only copy of the session setup would leave, in a core of its own,
/// so nothing done in it reaches the person's Crest and no page in it keeps
/// website data. Each change to setup reaches the copy: a new name or look as
/// Crest applies one, and a Space or tab that comes or goes by opening the
/// copy again, keeping what the person changed in the copy's tabs and
/// folders.
@MainActor
@Observable
final class MobileSetupLiveSession {
    // MARK: - Types

    /// One opening of the copy: its browser and what the browser runs on.
    @MainActor
    struct Copy: Identifiable {
        let id = UUID()
        let store: BrowserStore
        let pages: MobileBrowserPageStore
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: true, initiallyShowsCompactPage: false, allowsCompactFloatingSidebar: false)
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
    }

    // MARK: - Variables

    /// The copy, once there is a session to show.
    private(set) var copy: Copy?
    @ObservationIgnored private let core = CrestCore()
    /// The session the copy shows now.
    @ObservationIgnored private var shown: SessionState.Seed?

    /// What the person changed in the copy, against the session it opened on,
    /// or nil when they changed nothing.
    var edits: BrowserSetupCopyEdits? {
        guard let copy, let shown else { return nil }
        let edits = BrowserSetupCopyEdits(from: shown, to: copy.store.spaceModels.map(\.value))
        return edits.isEmpty ? nil : edits
    }

    /// The look of the Space the copy shows now, which the room around the
    /// copy wears.
    var shownLook: SpaceBranding? {
        copy?.store.shownSpace?.settings.look
    }

    // MARK: - Mutators

    /// Shows `seed`, whose tabs wear `images`, on Space `spaceID` when it
    /// names one: as changes to the copy while it holds the same Spaces,
    /// folders and tabs, or else as a new copy.
    func show(_ seed: SessionState.Seed, images: [UUID: Data], spaceID: UUID?) {
        if let shown, let copy, shown.setupOutline == seed.setupOutline {
            copy.store.wearSetup(seed, over: shown)
        } else {
            // What the person changed in this copy carries into the next.
            let carried = edits
            copy?.store.close()
            let store = BrowserStore(seed: seed, images: images, showing: spaceID, core: core)
            carried?.replay(into: store)
            let pages = MobileBrowserPageStore(browser: store, usesEphemeralWebsiteDataStores: true)
            store.tabLinkProvider = pages
            store.tabCopying = pages
            copy = Copy(store: store, pages: pages)
        }
        shown = seed
        show(spaceID)
    }

    /// Shows Space `spaceID` in the copy, on a Start Page.
    func show(_ spaceID: UUID?) {
        guard let spaceID else { return }
        copy?.store.showSetupSpace(spaceID)
    }

    /// Shows the Getting Started guide in the copy's first Space, as Crest
    /// opens on it once setup finishes, so the copy grows into the browser
    /// showing the same page.
    func showGettingStarted() {
        guard let store = copy?.store, let first = store.spaceModels.first else { return }
        store.showSetupSpace(first.id)
        store.openGettingStarted()
    }

    /// Lets the copy go.
    func close() {
        copy?.store.close()
        copy = nil
        shown = nil
    }
}
