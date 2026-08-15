import AppKit

@MainActor
final class ShortcutRecorderButton: NSButton {
    var restingTitle = BrowserShortcutSettingsPresentation.emptyShortcutGlyph {
        didSet {
            guard !isRecording else { return }
            title = restingTitle
        }
    }

    var recordingTitle = BrowserShortcutLocalization.string(
        BrowserShortcutSettingsPresentation.typeShortcut,
        locale: .current
    ) {
        didSet {
            guard isRecording else { return }
            title = recordingTitle
        }
    }

    var eventHandler: ((NSEvent, ShortcutRecorderButton) -> Void)?

    private(set) var isRecording = false
    private var eventMonitor: Any?

    var hasActiveEventMonitor: Bool {
        eventMonitor != nil
    }

    override var acceptsFirstResponder: Bool { true }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = recordingTitle
        bezelColor = .controlAccentColor
        window?.makeFirstResponder(self)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard
                let self,
                self.isRecording,
                self.window?.isKeyWindow == true
            else {
                return event
            }
            self.eventHandler?(event, self)
            return nil
        }
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        title = restingTitle
        bezelColor = nil
        removeEventMonitor()
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            isRecording = false
            title = restingTitle
            bezelColor = nil
            removeEventMonitor()
        }
        return resigned
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}
