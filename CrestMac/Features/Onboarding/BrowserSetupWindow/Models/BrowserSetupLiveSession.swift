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
    /// Whether the welcome has dressed the copy in a look of its own.
    @ObservationIgnored private var isIdling = false
    /// The view the copy's browser draws in, which crossfades where a look
    /// changes in a way colors cannot mix.
    @ObservationIgnored weak var browserView: NSView?
    /// The change of look under way, which a newer one replaces.
    @ObservationIgnored private var morph: Task<Void, Never>?
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
            if isIdling { settle() }
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

    /// Dresses the Space the copy shows in `look`, changing into it in front
    /// of the person, as the welcome shows what Crest can look like;
    /// `settle()` puts setup's own looks back.
    func idle(in look: SpaceBranding) {
        guard let copy, let space = copy.store.shownSpace else { return }
        isIdling = true
        change(space.id, from: space.settings.look, to: look, over: CrestMotion.onboardingBackdropFade)
    }

    /// Puts back the looks setup gives the copy's Spaces, after the welcome
    /// dressed it in others: the Space it shows changes back in front of the
    /// person, the rest at once.
    func settle() {
        guard isIdling, let copy, let shown else { return }
        isIdling = false
        guard let space = copy.store.shownSpace,
            let own = shown.spaces.first(where: { $0.id == space.id })?.settings.branding
        else {
            morph?.cancel()
            copy.store.wearLooks(of: shown)
            return
        }
        change(space.id, from: space.settings.look, to: own, over: CrestMotion.onboardingStepTransition) {
            copy.store.wearLooks(of: shown)
        }
    }

    /// Changes Space `spaceID` of the copy from `start` into `end` over
    /// `duration`, frame by frame, each frame the look as far along as the
    /// time says, so every surface, materials included, changes together and
    /// a slow frame skips ahead rather than holding the change back. Halfway
    /// the browser crossfades briefly over the parts that cannot mix; where
    /// the text turns between light and dark, which turns the materials too,
    /// a veil in the window's own colors covers the turn.
    private func change(
        _ spaceID: UUID, from start: SpaceBranding, to end: SpaceBranding, over duration: TimeInterval,
        then finish: (@MainActor () -> Void)? = nil
    ) {
        morph?.cancel()
        guard let copy else { return }
        morph = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let began = clock.now
            var tone = start.foregroundTone(over: .dark)
            var hasSwapped = false
            while !Task.isCancelled {
                let progress = min(Self.seconds(began.duration(to: clock.now)) / duration, 1)
                let amount = Self.eased(progress)
                let look = progress >= 1 ? end : start.blended(toward: end, by: amount)
                let lookTone = look.foregroundTone(over: .dark)
                if lookTone != tone {
                    await self?.veiling(look) { copy.store.wearLook(look, on: spaceID) }
                } else {
                    if !hasSwapped, amount >= 0.5 { self?.crossfade() }
                    copy.store.wearLook(look, on: spaceID)
                }
                hasSwapped = hasSwapped || amount >= 0.5
                tone = lookTone
                guard progress < 1 else { break }
                try? await Task.sleep(for: BrowserSetupLiveSessionMetrics.frame)
            }
            guard !Task.isCancelled else { return }
            finish?()
        }
    }

    /// Crossfades the copy's whole browser, its AppKit views included, from
    /// how it draws now into how it draws next, briefly, over a part of a look
    /// that cannot mix. The fade starts before the change, so no part of the
    /// browser that redraws first shows it early.
    private func crossfade() {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = BrowserSetupLiveSessionMetrics.swapFade
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        browserView?.layer?.add(fade, forKey: BrowserSetupLiveSessionMetrics.fadeKey)
    }

    /// Makes `turn` behind a veil in `look`'s Background, the colors the
    /// window wears at that moment: the veil rises over the browser, `turn`
    /// happens out of sight, and the veil falls while the change goes on.
    /// A material turning between light and dark cannot fade, as it draws
    /// what lies behind it live.
    private func veiling(_ look: SpaceBranding, _ turn: () -> Void) async {
        guard let view = browserView, let layer = view.layer else {
            turn()
            return
        }
        let veil = CAGradientLayer()
        veil.frame = layer.bounds
        veil.zPosition = BrowserSetupLiveSessionMetrics.veilLevel
        let fill = look.backgroundFill
        let colors = fill.colors.count > 1 ? fill.colors : [fill.colors[0], fill.colors[0]]
        veil.colors = colors.map { NSColor($0.color).cgColor }
        let angle = fill.degrees * .pi / 180
        // Unit points run down the layer when its geometry is flipped, as a
        // flipped view's is, and up it otherwise.
        let down = layer.isGeometryFlipped ? 1.0 : -1.0
        veil.startPoint = CGPoint(x: 0.5 - cos(angle) / 2, y: 0.5 - down * sin(angle) / 2)
        veil.endPoint = CGPoint(x: 0.5 + cos(angle) / 2, y: 0.5 + down * sin(angle) / 2)
        veil.opacity = 0
        layer.addSublayer(veil)
        Self.fade(veil, to: BrowserSetupLiveSessionMetrics.veilOpacity, over: BrowserSetupLiveSessionMetrics.veilRise)
        try? await Task.sleep(for: .seconds(BrowserSetupLiveSessionMetrics.veilRise))
        turn()
        try? await Task.sleep(for: BrowserSetupLiveSessionMetrics.frame)
        Self.fade(veil, to: 0, over: BrowserSetupLiveSessionMetrics.veilFall)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BrowserSetupLiveSessionMetrics.veilFall))
            veil.removeFromSuperlayer()
        }
    }

    /// Fades `layer` to `opacity` over `duration`, with no other animation
    /// joining in.
    private static func fade(_ layer: CALayer, to opacity: Float, over duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.add(animation, forKey: "opacity")
        layer.opacity = opacity
        CATransaction.commit()
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }

    /// How far a change has come by `progress` of its time: easing out of
    /// the old look and into the new one.
    private static func eased(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
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
        morph?.cancel()
        pacing?.cancel()
        pacing = nil
        waiting = nil
        copy?.store.close()
        copy = nil
        shown = nil
        isIdling = false
    }
}

enum BrowserSetupLiveSessionMetrics {
    static let fadeKey = "look"
    /// How often at most the copy takes a change while changes come quickly.
    static let changeInterval = Duration.milliseconds(66)
    /// How often a change of look moves on.
    static let frame = Duration.milliseconds(33)
    /// How long the browser crossfades over a part of a look that cannot mix.
    static let swapFade: TimeInterval = 0.45
    /// The veil over a turn between light and dark: how opaque it rises, how
    /// long it takes to rise and to fall, and where it stands over the
    /// browser's own layers.
    static let veilOpacity: Float = 0.92
    static let veilRise: TimeInterval = 0.2
    static let veilFall: TimeInterval = 0.4
    static let veilLevel: CGFloat = 10_000
}
