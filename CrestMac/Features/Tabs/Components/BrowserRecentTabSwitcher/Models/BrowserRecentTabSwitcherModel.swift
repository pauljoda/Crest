import AppKit
import Observation

/// A walk back through the active tabs of the Space a window shows, from the
/// most recently used, for as long as the modifier keys that started it stay
/// held.
///
/// Each press of the walk's key steps one tab further and Shift steps back, as
/// the Command-Tab app switcher does. Letting the modifiers go shows the tab
/// the walk rests on, and Escape ends it where it started. The switcher only
/// appears once a walk lasts a moment, so a quick tap of the shortcut shows
/// the most recent tab without anything flashing on screen.
@Observable
@MainActor
final class BrowserRecentTabSwitcherModel {
    // MARK: - Types

    /// What a walk in progress holds on to: the key that steps it, the
    /// modifiers that keep it going, and what shows the tab it ends on. The
    /// key is the physical one the person's shortcut uses, whatever it is
    /// bound to, so holding Shift to step back cannot turn it into another
    /// character.
    private struct Walk {
        let keyCode: UInt16
        let held: NSEvent.ModifierFlags
        let show: @MainActor (UUID) -> Void
        let modifierMonitor: Any?
        let pointerMonitor: Any?
        let resignObserver: NSObjectProtocol
        var reveal: Task<Void, Never>?
    }

    // MARK: - Static Variables

    /// How long a walk lasts before the switcher appears.
    static let revealDelay: Duration = .milliseconds(160)

    /// The modifiers that can hold a walk open. Shift reverses a step rather
    /// than holding the walk.
    private static let holdingModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

    /// The pointer's movement, which a walk keeps from everything under the
    /// switcher: pages and their engines follow the pointer themselves, so
    /// covering them is not enough to keep them from lighting up.
    private static let pointerMotion: NSEvent.EventTypeMask = [.mouseMoved, .mouseEntered, .mouseExited]

    // MARK: - Variables

    /// The stops the walk passes, a tab or a whole split each, the one shown
    /// when it started first.
    private(set) var stops: [RecentTabStop] = []

    /// The position in `stops` the walk rests on.
    private(set) var selectedIndex = 0

    /// Whether the switcher is on screen.
    private(set) var isRevealed = false

    /// A picture of each tab's page the walk has been handed, kept only while
    /// it lasts.
    private(set) var previews: [UUID: BrowserPageSnapshotImage] = [:]

    @ObservationIgnored private var walk: Walk?

    /// Where each tile of the walk sits in its window, by its place in the walk.
    @ObservationIgnored private var tileFrames: [Int: CGRect] = [:]

    /// Whether a walk is in progress, which then takes every key down.
    var isWalking: Bool { walk != nil }

    /// The tab showing the stop the walk rests on shows.
    var selectedTabID: UUID? {
        stops.indices.contains(selectedIndex) ? stops[selectedIndex].tabID : nil
    }

    // MARK: - Actions - Walking

    /// Starts a walk through `stops` one step in, when `event` is a key down
    /// with a modifier held that can keep it going, and answers whether it
    /// did. A command run any other way, as from the menu or the launcher,
    /// starts none, so its caller just shows the most recent tab. With no
    /// other active tab the walk still starts, resting on the shown one, as
    /// the app switcher does with one app open, so the shortcut never jumps to
    /// a tab the walk would pass over. A walk asks `preview` for a picture of
    /// each tab's page as it starts, every member of a split included, so the
    /// pictures are there by the time the switcher appears.
    func begin(
        _ stops: [RecentTabStop], from event: NSEvent?,
        preview: (UUID, @escaping @MainActor (BrowserPageSnapshotImage?) -> Void) -> Void,
        show: @escaping @MainActor (UUID) -> Void
    ) -> Bool {
        guard walk == nil, !stops.isEmpty, let event, event.type == .keyDown else { return false }
        let held = event.modifierFlags.intersection(Self.holdingModifiers)
        guard !held.isEmpty else { return false }

        let modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.modifiersChanged(to: event.modifierFlags) }
            return event
        }
        let pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.pointerMotion) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(event) }
            return nil
        }
        // Another app in front never reports the modifiers going up here.
        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        self.stops = stops
        selectedIndex = min(1, stops.count - 1)
        isRevealed = false
        walk = Walk(
            keyCode: event.keyCode, held: held, show: show, modifierMonitor: modifierMonitor,
            pointerMonitor: pointerMonitor, resignObserver: resignObserver,
            reveal: Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.revealDelay)
                guard !Task.isCancelled else { return }
                self?.isRevealed = true
            })
        for tabID in stops.flatMap(\.members) {
            preview(tabID) { [weak self] image in self?.keep(image, of: tabID) }
        }
        return true
    }

    /// Takes a key down while a walk is in progress, and answers whether it
    /// was taken: every key is, so none reaches the page or a field under
    /// the switcher.
    func handle(_ event: NSEvent) -> Bool {
        guard let walk, event.type == .keyDown else { return false }
        let key = BrowserShortcutKey(event: event)
        if key == .special(.escape) {
            cancel()
        } else if event.keyCode == walk.keyCode {
            step(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        } else if key == .special(.returnKey) {
            finish()
        } else if key == .special(.upArrow) {
            step(by: -1)
        } else if key == .special(.downArrow) {
            step(by: 1)
        }
        return true
    }

    /// Rests the walk on the stop at `index`, as the pointer moving onto its
    /// tile does.
    func select(_ index: Int) {
        guard isWalking, stops.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Records where the tile of the tab at `index` sits in its window, from
    /// the window's top left, so the pointer moving onto it can pick it.
    func place(_ index: Int, at frame: CGRect) {
        tileFrames[index] = frame
    }

    /// Ends the walk on the tab at `index`, as clicking its tile does.
    func choose(_ index: Int) {
        select(index)
        finish()
    }

    /// Ends the walk, showing the tab it rests on.
    func finish() {
        guard let walk else { return }
        let chosen = selectedIndex == 0 ? nil : selectedTabID
        end()
        if let chosen { walk.show(chosen) }
    }

    /// Ends the walk on the tab it started from.
    func cancel() {
        end()
    }

    /// Shows the switcher at once rather than once the walk lasts a moment, as
    /// when it takes the place of a surface the person is already looking at.
    func reveal() {
        guard let walk else { return }
        walk.reveal?.cancel()
        isRevealed = true
    }

    // MARK: - Mutators

    /// Moves `offset` stops along the walk, wrapping at either end, and shows
    /// the switcher at once, since a second press means the person is looking.
    private func step(by offset: Int) {
        guard !stops.isEmpty else { return }
        selectedIndex = (selectedIndex + offset % stops.count + stops.count) % stops.count
        reveal()
    }

    /// Keeps a picture of a tab the walk passes; one that arrives after the
    /// walk ended, or for no page, is dropped.
    private func keep(_ image: BrowserPageSnapshotImage?, of tabID: UUID) {
        guard isWalking, let image, stops.contains(where: { $0.members.contains(tabID) }) else { return }
        previews[tabID] = image
    }

    /// Rests the walk on the tile the pointer moved onto once the switcher is
    /// on screen. Only movement counts, so a pointer that happens to rest
    /// where a tile appears does not pick it.
    private func pointerMoved(_ event: NSEvent) {
        guard isRevealed, event.type == .mouseMoved, let view = event.window?.contentView else { return }
        var point = view.convert(event.locationInWindow, from: nil)
        if !view.isFlipped { point.y = view.bounds.height - point.y }
        guard let index = tileFrames.first(where: { $0.value.contains(point) })?.key else { return }
        select(index)
    }

    private func modifiersChanged(to flags: NSEvent.ModifierFlags) {
        guard let walk, !flags.intersection(.deviceIndependentFlagsMask).isSuperset(of: walk.held) else { return }
        finish()
    }

    private func end() {
        guard let walk else { return }
        walk.reveal?.cancel()
        if let modifierMonitor = walk.modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        if let pointerMonitor = walk.pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        NotificationCenter.default.removeObserver(walk.resignObserver)
        self.walk = nil
        isRevealed = false
        stops = []
        previews = [:]
        tileFrames = [:]
        selectedIndex = 0
    }
}
