import AppKit

/// The keys a person types into a window while its command palette is on its
/// way, from the shortcut or click that opens it until its field takes the
/// keyboard. The palette needs a moment to appear, and a focused page takes a
/// moment to let go of a shortcut it sees first; keys typed meanwhile would
/// reach the page, or nothing. Held here instead, they reach the field once
/// it has the keyboard, in the order they were typed, as if it had been there
/// all along. Keys held for a palette that closes first or never takes the
/// keyboard, or for a shortcut the page kept, go where they would have gone.
///
/// Crest's own shortcuts still run as they are pressed: the shell sees each
/// key before the palette does.
@MainActor
final class BrowserCommandPaletteTypeahead {
    // MARK: - Static Variables

    /// How long keys wait for a field that never takes the keyboard.
    private static let patience: Duration = .seconds(1)
    /// The keys the window whose palette is on its way holds. Only the key
    /// window takes keys, so one window holds them at a time.
    private static var holding: BrowserCommandPaletteTypeahead?

    // MARK: - Variables

    private weak var window: NSWindow?
    /// Whether the keys wait on a focused page's answer to a shortcut that
    /// opens the palette, rather than on a palette that is opening.
    private var awaitsPage: Bool
    private var held: [NSEvent] = []
    private var monitor: Any?
    private var patienceTask: Task<Void, Never>?

    // MARK: - Initializers

    private init(window: NSWindow, awaitsPage: Bool) {
        self.window = window
        self.awaitsPage = awaitsPage
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) {
            [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            held.append(event)
            return nil
        }
        waitPatiently()
    }

    // MARK: - Actions

    /// Holds the keys typed into `window` from now on, as its palette opens,
    /// keeping any it already holds.
    static func hold(in window: NSWindow?) {
        take(window, awaitingPage: false)
    }

    /// Holds the keys typed into `window` from now on, while its focused page
    /// decides whether it keeps a shortcut that would open the palette.
    static func awaitPage(in window: NSWindow?) {
        take(window, awaitingPage: true)
    }

    /// Lets the page in `window` have the keys typed since it kept the
    /// shortcut, unless a palette is on its way there all the same.
    static func pageKept(in window: NSWindow?) {
        guard let holding, holding.window === window, holding.awaitsPage else { return }
        release()
    }

    /// Hands the keys held for `window` to its palette's field, which has
    /// just taken the keyboard: they come next, ahead of anything typed since.
    static func handOver(in window: NSWindow) {
        guard holding?.window === window else { return }
        release()
    }

    /// Stops holding keys, and puts those held back at the front of the event
    /// queue, in order, for whatever has the keyboard now.
    static func release() {
        guard let typeahead = holding else { return }
        holding = nil
        typeahead.patienceTask?.cancel()
        if let monitor = typeahead.monitor { NSEvent.removeMonitor(monitor) }
        for event in typeahead.held.reversed() { NSApp.postEvent(event, atStart: true) }
    }

    /// Holds keys for `window`, carrying on with those it already holds. Once
    /// a palette is on its way, the keys wait for it, whatever the page says.
    private static func take(_ window: NSWindow?, awaitingPage: Bool) {
        if let holding, let window, holding.window === window {
            holding.awaitsPage = holding.awaitsPage && awaitingPage
            holding.waitPatiently()
            return
        }
        release()
        holding = window.map { BrowserCommandPaletteTypeahead(window: $0, awaitsPage: awaitingPage) }
    }

    /// Lets go of the keys if nothing takes them in time.
    private func waitPatiently() {
        patienceTask?.cancel()
        patienceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled, let self, Self.holding === self else { return }
            Self.release()
        }
    }
}
