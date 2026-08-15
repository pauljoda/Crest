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
            NSApp.keyWindow?.title == ProductIdentity.name,
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
}
