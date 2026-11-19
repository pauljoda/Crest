import SwiftUI

/// The browser setup builds, as a window of Crest itself runs it: a
/// memory-only copy of the session setup would leave, in a core of its own,
/// so nothing done in it reaches the person's Crest and no page in it keeps
/// website data. Each change to setup reaches the copy: a new name or look
/// as Crest applies one, and a Space or tab that comes or goes by opening
/// the copy again. While changes come quickly, as a color is dragged, the
/// copy, a whole browser to redraw, takes the first at once and then the
/// newest at most every `changeInterval`, so the controls the person drags
/// keep their pace.
@MainActor
@Observable
final class BrowserSetupLiveSession {
    // MARK: - Types

    /// One opening of the copy: its window and what the window runs on.
    @MainActor
    struct Copy: Identifiable {
        let id = UUID()
        let store: BrowserStore
        let pages: BrowserPagePool
        let chrome = BrowserChromeState(sidebarIsPresented: true)
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
    }

    // MARK: - Variables

    /// The copy's window, once there is a session to show.
    private(set) var copy: Copy?
    @ObservationIgnored private let core = CrestCore()
    /// The session the copy shows now.
    @ObservationIgnored private var shown: SessionState.Seed?
    /// The wait before the copy takes another change, while one is under way.
    @ObservationIgnored private var pacing: Task<Void, Never>?
    /// The newest change that came during the wait, which the copy takes
    /// when it ends.
    @ObservationIgnored private var waiting: (seed: SessionState.Seed, images: [UUID: Data], spaceID: UUID?)?

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
            guard pacing == nil else {
                waiting = (seed, images, spaceID)
                return
            }
            copy.store.wearSetup(seed, over: shown)
            pace()
        } else {
            pacing?.cancel()
            pacing = nil
            waiting = nil
            // What the person changed in this copy carries into the next.
            let carried = edits
            copy?.store.close()
            let store = BrowserStore(seed: seed, images: images, showing: spaceID, core: core)
            carried?.replay(into: store)
            copy = Copy(store: store, pages: BrowserPagePool(browser: store, usesEphemeralWebsiteDataStores: true))
        }
        shown = seed
        show(spaceID)
    }

    /// Shows Space `spaceID` in the copy's window, on a Start Page, as Crest
    /// enters a Space whose pages are not loaded: no page in the copy loads.
    func show(_ spaceID: UUID?) {
        guard let spaceID else { return }
        copy?.store.showSetupSpace(spaceID)
    }

    /// Opens the Getting Started guide on the copy's first Space, as Crest
    /// opens once setup finishes, so the preview grows into the window Crest
    /// opens in its place.
    func showGettingStarted() {
        guard let store = copy?.store, let first = store.spaceModels.first else { return }
        store.showSetupSpace(first.id)
        store.openGettingStarted()
    }

    /// Holds the copy's next change back for `changeInterval`, then gives it
    /// the newest that came meanwhile.
    private func pace() {
        pacing = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserSetupLiveSessionMetrics.changeInterval)
            guard let self, !Task.isCancelled else { return }
            pacing = nil
            if let waiting {
                self.waiting = nil
                show(waiting.seed, images: waiting.images, spaceID: waiting.spaceID)
            }
        }
    }

    /// Lets the copy go.
    func close() {
        pacing?.cancel()
        pacing = nil
        waiting = nil
        copy?.store.close()
        copy = nil
        shown = nil
    }
}

enum BrowserSetupLiveSessionMetrics {
    /// How often at most the copy takes a change while changes come quickly.
    static let changeInterval = Duration.milliseconds(66)
}
