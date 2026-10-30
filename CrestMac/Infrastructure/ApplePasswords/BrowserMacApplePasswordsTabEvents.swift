import SwiftUI

/// Tells the Apple Passwords helper which Crest tab is in front and which
/// tabs closed, as Apple's extension does for Chrome's tabs. It only reads
/// what the windows' stores show; the core owns the tabs.
///
/// Nothing is sent unless the helper already runs. A private window has no
/// Apple Passwords access, so its store never reaches this class, and an
/// isolated launch never starts the helper.
@MainActor
final class BrowserMacApplePasswordsTabEvents {
    // MARK: - Types

    /// What one window showed when it was last followed.
    private struct Snapshot {
        var shownTab: UUID?
        var tabs: Set<UUID>
    }

    // MARK: - Variables

    private let helper: ApplePasswordsHelper
    private let launchEnvironment: BrowserLaunchEnvironment
    private var snapshots: [UUID: Snapshot] = [:]

    // MARK: - Initializers

    init(helper: ApplePasswordsHelper, launchEnvironment: BrowserLaunchEnvironment = .current) {
        self.helper = helper
        self.launchEnvironment = launchEnvironment
    }

    // MARK: - Actions - Following

    /// The window's session moved: tells the helper about a newly selected tab
    /// when the window is the key window, and about tabs that closed.
    func follow(_ store: BrowserStore, windowIsKey: Bool) {
        guard permits(store) else { return }
        let shown = store.selectedTabID(in: store.selectedSpaceID)
        let tabs = Set(store.spaceModels.flatMap { $0.tabs.models.map(\.id) })
        let previous = snapshots[store.windowID]
        snapshots[store.windowID] = Snapshot(shownTab: shown, tabs: tabs)
        for closed in (previous?.tabs ?? []).subtracting(tabs) { helper.tabClosed(closed) }
        if windowIsKey, let shown, shown != previous?.shownTab { helper.tabActivated(shown) }
    }

    /// A Crest window came to the front: tells the helper which tab it shows.
    func windowBecameKey(_ store: BrowserStore) {
        guard permits(store) else { return }
        let shown = store.selectedTabID(in: store.selectedSpaceID)
        snapshots[store.windowID, default: Snapshot(shownTab: nil, tabs: [])].shownTab = shown
        if let shown { helper.tabActivated(shown) }
    }

    /// A window closed: its tabs stay open in the Spaces, so only its record goes.
    func forget(_ store: BrowserStore) {
        snapshots[store.windowID] = nil
    }

    /// Events go only for standard windows, to a helper that runs.
    private func permits(_ store: BrowserStore) -> Bool {
        !store.isPrivateBrowsing && !launchEnvironment.requiresIsolation && helper.isRunning
    }
}

/// Follows a window's session for the tab events. It reads the store and sends
/// nothing itself, so a store without Apple Passwords is left alone.
struct BrowserMacApplePasswordsTabEventsFollowing: ViewModifier {
    let browser: BrowserStore
    let isWindowKey: () -> Bool

    func body(content: Content) -> some View {
        content.onChange(of: browser.sessionRevision) {
            (browser.applePasswords as? BrowserMacApplePasswords)?.tabEvents
                .follow(browser, windowIsKey: isWindowKey())
        }
    }
}
