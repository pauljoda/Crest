import AppKit
import Observation

/// The pinned extension tile somebody is carrying along a Space's strip: which
/// tile is off the strip, where the pointer has taken it, the slot the strip
/// holds open for it, and how its release lands.
///
/// One per window, owned by the window's root model as a Split View carry is,
/// so the preview the window draws can outlive the tile it came from. The
/// state answers what is carried and never where it may go: the strip
/// resolves the slot from the pointer, works out where that slot is, and
/// hands both in.
///
/// A release lands the preview on the slot the gap held, then fades it as the
/// tile shows there again, as a sidebar row's lift does. The strip shows the
/// order the release made until the engine reports it, so nothing steps back
/// while the engine saves it. Escape, or the window no longer being key, puts
/// the tile back where it came from.
@Observable
@MainActor
final class BrowserExtensionTileLiftState {
    // MARK: - Types

    struct Lift: Equatable {
        let extensionID: String
        /// The Space whose strip the tile came from, and its profile, which
        /// every strip of that profile shows the same order for.
        let spaceID: UUID
        let profileID: UUID
        let icon: NSImage?
        /// The tile's frame as the lift began, in the window's coordinates from
        /// its top left.
        let originFrame: CGRect
        /// Where the pointer took hold of the tile, from its top left.
        let grabOffset: CGSize
        /// The strip's tiles as the lift began, in order.
        let order: [String]
        var pointer: CGPoint
        /// The slot among the strip's tiles the gap holds open.
        var gapIndex: Int
        /// Where the tile lands, once it was let go.
        var landing: Landing?

        /// The tiles in the order letting go now leaves them.
        var droppedOrder: [String] {
            var order = order.filter { $0 != extensionID }
            order.insert(extensionID, at: min(max(gapIndex, 0), order.count))
            return order
        }

        /// The preview's top left: under the pointer, where it took hold.
        var origin: CGPoint {
            CGPoint(x: pointer.x - grabOffset.width, y: pointer.y - grabOffset.height)
        }
    }

    struct Landing: Equatable {
        /// The slot the tile lands in, in the window's coordinates.
        let frame: CGRect
        /// Whether the tile shows in its slot again, which the preview fades
        /// over.
        var isRevealing = false
    }

    // MARK: - Static Variables

    /// How long a tile ignores its own click once it was let go.
    static let activationSuppression: Duration = .milliseconds(250)
    /// How long the preview fades once the tile shows again.
    static let revealDuration: TimeInterval = 0.10
    /// How long the strips wait for the engine to report the order a release
    /// made before they show the engine's own again.
    static let pendingOrderExpiration: Duration = .seconds(2)

    // MARK: - Variables

    private(set) var lift: Lift?
    /// The profile whose strips show the order a release made, and that order,
    /// until the engine reports it.
    private(set) var pendingOrder: (profileID: UUID, order: [String])?
    private(set) var isSuppressingActivation = false
    @ObservationIgnored private var landingTask: Task<Void, Never>?
    @ObservationIgnored private var suppressionTask: Task<Void, Never>?
    @ObservationIgnored private var pendingOrderTask: Task<Void, Never>?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var windowObservers: [NSObjectProtocol] = []

    /// Whether a tile is on the pointer now, rather than landing.
    var isCarrying: Bool { lift != nil && lift?.landing == nil }

    /// Whether a tile's click stands aside: one is being carried or was just
    /// let go.
    var suppressesActivation: Bool { isCarrying || isSuppressingActivation }

    // MARK: - Actions - Strips

    /// Whether the strip of `spaceID` leaves the tile `extensionID` out of
    /// sight, as it is on the pointer or landing on its slot.
    func hidesTile(_ extensionID: String, in spaceID: UUID) -> Bool {
        guard let lift, lift.extensionID == extensionID, lift.spaceID == spaceID else { return false }
        return lift.landing?.isRevealing != true
    }

    /// The order the strips of `profileID` show for `order`, the engine's: the
    /// one a release made while the engine has yet to report it.
    func shownOrder(_ order: [String], profileID: UUID) -> [String] {
        guard let pendingOrder, pendingOrder.profileID == profileID, pendingOrder.order != order else { return order }
        let rank = Dictionary(
            pendingOrder.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return order.enumerated()
            .sorted { (rank[$0.element] ?? order.count + $0.offset) < (rank[$1.element] ?? order.count + $1.offset) }
            .map(\.element)
    }

    /// The strip of `spaceID` now shows `ids`, and can be reordered or not. A
    /// tile carried from it goes once the strip no longer shows the tiles it
    /// was lifted among, as when its extension updates or is unpinned
    /// elsewhere, or once the strip can't be reordered: the carried tile's
    /// drag may never hear its release.
    func stripChanged(to ids: [String], in spaceID: UUID, isReorderable: Bool) {
        guard let lift, lift.landing == nil, lift.spaceID == spaceID else { return }
        let stands = isReorderable && ids.count > 1 && Set(ids) == Set(lift.order)
        guard !stands else { return }
        abandon()
    }

    /// The engine reported `order` for the strips of `profileID`. Once it is
    /// the order a release made, the strips show the engine's own again.
    func engineReported(_ order: [String], profileID: UUID) {
        guard let pendingOrder, pendingOrder.profileID == profileID, pendingOrder.order == order else { return }
        self.pendingOrder = nil
        pendingOrderTask?.cancel()
    }

    // MARK: - Actions - Carrying

    /// Takes `extensionID`'s tile off the strip of `spaceID`, whose tiles are
    /// `order`, at `frame`, held where `pointer` took it. Escape or the window
    /// no longer being key puts it back.
    func begin(
        extensionID: String, spaceID: UUID, profileID: UUID, icon: NSImage?, frame: CGRect, pointer: CGPoint,
        order: [String]
    ) {
        guard lift == nil, let index = order.firstIndex(of: extensionID) else { return }
        landingTask?.cancel()
        lift = Lift(
            extensionID: extensionID, spaceID: spaceID, profileID: profileID, icon: icon, originFrame: frame,
            grabOffset: CGSize(width: pointer.x - frame.minX, height: pointer.y - frame.minY), order: order,
            pointer: pointer, gapIndex: index)
        watch(NSApp.keyWindow)
    }

    /// Moves the carried tile with the pointer, the strip holding `gapIndex`
    /// open for it.
    func update(pointer: CGPoint, gapIndex: Int) {
        guard var lift, lift.landing == nil else { return }
        lift.pointer = pointer
        lift.gapIndex = min(max(gapIndex, 0), lift.order.count - 1)
        guard lift != self.lift else { return }
        self.lift = lift
    }

    /// Lets the carried tile go onto the slot the gap holds, at `frame`, and
    /// answers the move to make: the tile and the one it now stands before,
    /// or nil before none. Nil when the tile went back where it was.
    func drop(landingAt frame: CGRect) -> (extensionID: String, beforeID: String?)? {
        guard let lift, lift.landing == nil else { return nil }
        let order = lift.droppedOrder
        land(at: frame)
        guard order != lift.order, let index = order.firstIndex(of: lift.extensionID) else { return nil }
        pendingOrder = (lift.profileID, order)
        pendingOrderTask?.cancel()
        pendingOrderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.pendingOrderExpiration)
            guard !Task.isCancelled else { return }
            self?.pendingOrder = nil
        }
        return (lift.extensionID, order.indices.contains(index + 1) ? order[index + 1] : nil)
    }

    /// Puts the carried tile back on the slot it came from, with nothing moved.
    func cancel() {
        guard var lift, lift.landing == nil, let index = lift.order.firstIndex(of: lift.extensionID) else { return }
        lift.gapIndex = index
        self.lift = lift
        land(at: lift.originFrame)
    }

    /// Ends a lift at once, landing or not, as when its strip goes away.
    func abandon() {
        landingTask?.cancel()
        stopWatching()
        lift = nil
    }

    // MARK: - Actions - Landing

    /// Lands the preview on `frame`, shows the tile there once it arrived,
    /// and ends the lift once the preview faded over it.
    private func land(at frame: CGRect) {
        guard var lift else { return }
        stopWatching()
        lift.landing = Landing(frame: frame)
        self.lift = lift
        suppressActivation()
        landingTask?.cancel()
        landingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(CrestMotion.dragSourceTransition))
            guard !Task.isCancelled, let self, var lift = self.lift else { return }
            lift.landing?.isRevealing = true
            self.lift = lift
            try? await Task.sleep(for: .seconds(Self.revealDuration))
            guard !Task.isCancelled else { return }
            self.lift = nil
        }
    }

    private func suppressActivation() {
        isSuppressingActivation = true
        suppressionTask?.cancel()
        suppressionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.activationSuppression)
            guard !Task.isCancelled else { return }
            self?.isSuppressingActivation = false
        }
    }

    // MARK: - Actions - Cancelling

    /// Puts the tile back when the person presses Escape in `window`, or the
    /// window stops being key or closes.
    private func watch(_ window: NSWindow?) {
        stopWatching()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .escape else { return event }
            let cancelled = MainActor.assumeIsolated {
                guard let self, self.isCarrying else { return false }
                self.cancel()
                return true
            }
            return cancelled ? nil : event
        }
        guard let window else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancel() }
                })
        }
    }

    private func stopWatching() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }
}
