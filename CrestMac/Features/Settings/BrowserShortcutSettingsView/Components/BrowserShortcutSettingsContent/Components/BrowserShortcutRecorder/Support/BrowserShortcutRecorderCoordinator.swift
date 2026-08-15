import AppKit

@MainActor
final class BrowserShortcutRecorderCoordinator: NSObject {
    private var record: (BrowserShortcut?) -> Void
    private var reportInvalidShortcut: () -> Void

    init(
        record: @escaping (BrowserShortcut?) -> Void,
        reportInvalidShortcut: @escaping () -> Void
    ) {
        self.record = record
        self.reportInvalidShortcut = reportInvalidShortcut
    }

    func update(
        record: @escaping (BrowserShortcut?) -> Void,
        reportInvalidShortcut: @escaping () -> Void
    ) {
        self.record = record
        self.reportInvalidShortcut = reportInvalidShortcut
    }

    @objc func beginRecording(_ sender: ShortcutRecorderButton) {
        sender.beginRecording()
    }

    func handle(_ event: NSEvent, sender: ShortcutRecorderButton) {
        let modifiers = BrowserShortcutModifiers(event.modifierFlags)
        if modifiers.isEmpty,
            let specialKey = BrowserShortcutSpecialKey(keyCode: event.keyCode)
        {
            switch specialKey {
            case .escape:
                sender.endRecording()
                return
            case .delete, .forwardDelete:
                record(nil)
                sender.endRecording()
                return
            default:
                break
            }
        }

        guard let key = BrowserShortcutKey(event: event) else {
            reportInvalidShortcut()
            return
        }
        let shortcut = BrowserShortcut(key: key, modifiers: modifiers)
        guard shortcut.isValid else {
            reportInvalidShortcut()
            return
        }
        record(shortcut)
        sender.endRecording()
    }
}
