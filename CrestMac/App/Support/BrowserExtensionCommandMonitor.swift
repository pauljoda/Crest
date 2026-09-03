import SwiftUI

@MainActor
final class BrowserExtensionCommandMonitor {
    private weak var browser: BrowserStore?
    private weak var extensionControllerPool: BrowserExtensionControllerPool?
    private weak var shortcuts: BrowserShortcutStore?
    private var eventMonitor: Any?

    init(
        browser: BrowserStore,
        extensionControllerPool: BrowserExtensionControllerPool,
        shortcuts: BrowserShortcutStore
    ) {
        self.browser = browser
        self.extensionControllerPool = extensionControllerPool
        self.shortcuts = shortcuts
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handle(event) ?? event
        }
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown,
            !event.isARepeat,
            Self.acceptsWindow(NSApp.keyWindow),
            !(NSApp.keyWindow?.firstResponder is ShortcutRecorderButton),
            let shortcut = BrowserShortcut(event: event),
            shortcut.isValid,
            let browser,
            let extensionControllerPool,
            let shortcuts
        else {
            return event
        }
        if !shortcuts.commands(assignedTo: shortcut).isEmpty
            || shortcut == Self.settingsShortcut
        {
            return event
        }
        return extensionControllerPool.performCommand(
            for: event,
            in: browser.session.selectedSpaceID
        ) ? nil : event
    }

    private static let settingsShortcut = BrowserShortcut(
        key: .character(","),
        modifiers: .command
    )

    /// Page titles are untrusted display text. Only the standard browser scene
    /// owns this monitor's store and extension pool, not private or utility windows.
    static func acceptsWindow(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue == BrowserSceneID.browser.rawValue
    }
}
