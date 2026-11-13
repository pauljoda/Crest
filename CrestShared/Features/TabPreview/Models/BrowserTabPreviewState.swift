import Foundation
import Observation

/// One window's tab preview: the tab or folder the pointer or the keyboard
/// rests on, and the one whose card shows.
///
/// A card shows once a tab has been rested on for `restDelay`. While one
/// shows, resting on another tab for `moveDelay` moves the card there. A tab
/// the pointer crosses while heading for the card, inside the triangle from
/// where it left the card's tab to the card's near edge, needs `aimDelay`
/// instead, so a pointer crossing other tabs or pins on its way into the
/// card keeps the card it aimed for. The card goes `leaveDelay` after the
/// pointer leaves both the tab and the card, or at once when dismissed. A
/// dismissed card stays away until a tab is entered again.
///
/// A card a finger held a row for shows at once and stays, whatever the
/// pointer does, until it is dismissed.
@MainActor
@Observable
final class BrowserTabPreviewState {
    // MARK: - Static Variables

    /// How long a tab is rested on before its card shows, while no card does.
    static let restDelay: Duration = .milliseconds(500)
    /// How long another tab is rested on, while a card shows, before the
    /// card moves to it.
    static let moveDelay: Duration = .milliseconds(120)
    /// How long a tab the pointer crosses while heading for the card is
    /// rested on before the card moves to it.
    static let aimDelay: Duration = .milliseconds(350)
    /// How long a card stays after the pointer leaves its tab and the card.
    static let leaveDelay: Duration = .milliseconds(150)
    /// How long after the person last typed in the window a card's search
    /// leaves the keyboard where it is.
    static let typingPause: TimeInterval = 1

    // MARK: - Variables

    /// The tab or folder whose card shows, or nil.
    private(set) var shown: BrowserTabPreviewTarget?
    /// Whether the pointer is over the card that shows.
    private(set) var isPointerInCard = false
    /// Whether the window draws cards. Rows and tiles report nothing to a
    /// window that doesn't.
    var isHosted: Bool { hosts > 0 }
    /// How many of the window's layers draw this preview's cards, as an
    /// iPad's does while the layout it leaves goes and the one it takes
    /// comes.
    private var hosts = 0
    /// Whether the card stays when the pointer leaves it, as while a folder's
    /// card holds a search.
    var isHeld = false
    /// Whether something the card began is under way, such as a tab dragged
    /// out of a folder's card or a row's menu, which the card stays up for.
    private(set) var isInteracting = false
    /// Where the card that shows is in the window, as its layer places it,
    /// which a folder card's tab cards lean on.
    var cardFrame: CGRect?
    /// Where the pointer is in the window, where the shell can tell. Without
    /// it, every tab moves the card after `moveDelay`.
    @ObservationIgnored var pointerLocation: (@MainActor () -> CGPoint?)?
    /// When the person last pressed a key in the window, where the shell can
    /// tell.
    @ObservationIgnored private var lastKeyPress: Date?
    /// The preview of the tabs a folder's card lists, drawn beside that card.
    @ObservationIgnored private(set) lazy var inner = BrowserTabPreviewState(parent: self)
    /// The preview whose folder card lists this one's tabs.
    @ObservationIgnored private weak var parent: BrowserTabPreviewState?
    @ObservationIgnored private var resting: BrowserTabPreviewTarget?
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// Where the pointer was as it left the card's tab, or as it entered the
    /// last tab it crossed heading for the card.
    @ObservationIgnored private var aimOrigin: CGPoint?

    /// Whether a card shows or one is on its way, which a click or a key in
    /// the window takes down.
    var isEngaged: Bool { shown != nil || resting != nil }

    /// Whether the person typed in the window a moment ago, so a card's
    /// search leaves the keyboard with what they were typing in.
    var isTyping: Bool {
        lastKeyPress.map { Date().timeIntervalSince($0) < Self.typingPause } ?? false
    }

    // MARK: - Initializers

    init() {}

    private init(parent: BrowserTabPreviewState) {
        self.parent = parent
    }

    // MARK: - Actions - Hosting

    /// One of the window's layers began or stopped drawing this preview's
    /// cards. Once none does, any card goes.
    func hostChanged(_ isHosting: Bool) {
        hosts = max(0, hosts + (isHosting ? 1 : -1))
        if hosts == 0 { dismiss() }
    }

    // MARK: - Actions - Resting

    /// A finger held `target`'s row: its card shows at once, in place of any
    /// other, and stays until dismissed.
    func hold(_ target: BrowserTabPreviewTarget) {
        waiting?.cancel()
        resting = nil
        aimOrigin = nil
        isPointerInCard = false
        inner.dismiss()
        shown = target
    }

    /// The pointer or the keyboard came to rest on `target`.
    func enter(_ target: BrowserTabPreviewTarget) {
        guard shown?.isHeldByTouch != true else { return }
        resting = target
        waiting?.cancel()
        if let shown, shown.key == target.key {
            self.shown = target
            return
        }
        let delay: Duration
        if shown == nil {
            delay = Self.restDelay
        } else if let location = pointerLocation?(), isHeadingForCard(to: location) {
            aimOrigin = location
            delay = Self.aimDelay
        } else {
            delay = Self.moveDelay
        }
        waiting = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !isPointerInCard, let resting, resting.key == target.key else {
                return
            }
            shown = resting
        }
    }

    /// The tab rested on moved, as when the sidebar scrolls under it.
    func move(_ target: BrowserTabPreviewTarget) {
        if let shown, shown.isHeldByTouch {
            if shown.key == target.key { self.shown = target.held(from: shown) }
            return
        }
        guard resting?.key == target.key else { return }
        resting = target
        if shown?.key == target.key { shown = target }
    }

    /// The pointer or the keyboard left the tab or folder `key` names.
    func leave(_ key: BrowserTabPreviewKey) {
        if shown?.key == key { aimOrigin = pointerLocation?() }
        guard resting?.key == key else { return }
        resting = nil
        waitToLeave()
    }

    /// The person pressed a key in the window.
    func keyPressed() {
        lastKeyPress = Date()
    }

    /// The pointer went into the card or out of it.
    func pointerInCardChanged(_ isInside: Bool) {
        guard isPointerInCard != isInside else { return }
        isPointerInCard = isInside
        if isInside {
            aimOrigin = nil
            waiting?.cancel()
        } else {
            waitToLeave()
            parent?.waitToLeave()
        }
    }

    /// Something the card began started or ended. Once it ends, the card goes
    /// unless the pointer is back on it.
    func interactionChanged(_ isInteracting: Bool) {
        guard self.isInteracting != isInteracting else { return }
        self.isInteracting = isInteracting
        if isInteracting {
            waiting?.cancel()
        } else {
            waitToLeave()
        }
    }

    /// Takes the card down at once, as on Escape, a click, a scroll or a key,
    /// and forgets the tab rested on, so the card comes back only when a tab
    /// is entered again.
    func dismiss() {
        waiting?.cancel()
        resting = nil
        aimOrigin = nil
        isPointerInCard = false
        isHeld = false
        if shown != nil { shown = nil }
        if parent == nil { inner.dismiss() }
    }

    /// Whether the pointer, now at `location`, is inside the triangle from
    /// where it left the card's tab to the card's near edge: on its way into
    /// the card rather than to the tab it crosses.
    private func isHeadingForCard(to location: CGPoint) -> Bool {
        guard let origin = aimOrigin, let card = cardFrame, location != origin else { return false }
        let edge = card.midX > origin.x ? card.minX : card.maxX
        let corners = (CGPoint(x: edge, y: card.minY), CGPoint(x: edge, y: card.maxY))
        func side(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (location.x - b.x) * (a.y - b.y) - (a.x - b.x) * (location.y - b.y)
        }
        let sides = [side(origin, corners.0), side(corners.0, corners.1), side(corners.1, origin)]
        return !(sides.contains { $0 < 0 } && sides.contains { $0 > 0 })
    }

    /// Takes the card down after `leaveDelay` unless the pointer is back on
    /// its tab, in it, or in the card of a tab it lists.
    private func waitToLeave() {
        waiting?.cancel()
        guard shown != nil, shown?.isHeldByTouch != true else { return }
        waiting = Task { [weak self] in
            try? await Task.sleep(for: Self.leaveDelay)
            guard !Task.isCancelled, let self, resting == nil, !isPointerInCard, !isHeld, !isInteracting else {
                return
            }
            if parent == nil, inner.isPointerInCard { return }
            shown = nil
            if parent == nil { inner.dismiss() }
        }
    }
}
