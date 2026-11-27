import AppKit
import SwiftUI

/// Displays a command's shortcut as a lightweight SwiftUI button while idle
/// and mounts the AppKit `ShortcutRecorderButton` only while actively
/// recording a new chord, avoiding dozens of `NSButton` bridges during scroll.
struct BrowserShortcutRecorder: View {
    @Environment(\.locale) private var locale
    @State private var isRecording = false

    let identifier: String
    let title: String
    let shortcut: BrowserShortcut?
    let record: (BrowserShortcut?) -> Void
    let reportInvalidShortcut: () -> Void

    var body: some View {
        if isRecording {
            BrowserShortcutRecorderBridge(
                identifier: identifier,
                title: title,
                shortcut: shortcut,
                record: record,
                reportInvalidShortcut: reportInvalidShortcut,
                onEndRecording: { isRecording = false }
            )
        } else {
            Button {
                isRecording = true
            } label: {
                Text(verbatim: displayTitle)
                    .font(
                        .system(
                            size: BrowserShortcutSettingsMetrics.recorderFontSize, weight: .medium, design: .monospaced)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier(BrowserShortcutSettingsAccessibilityID.recorderPrefix + identifier)
            .accessibilityLabel(
                Text(BrowserShortcutSettingsPresentation.recorderAccessibilityLabel(title: title))
            )
            .accessibilityValue(
                shortcut.map { Text(verbatim: $0.displayString(locale: locale)) }
                    ?? Text(BrowserShortcutSettingsPresentation.unassigned)
            )
            .accessibilityHint(Text(BrowserShortcutSettingsPresentation.recorderHelp))
            .help(Text(BrowserShortcutSettingsPresentation.recorderHelp))
        }
    }

    private var displayTitle: String {
        shortcut?.displayString(locale: locale)
            ?? BrowserShortcutSettingsPresentation.emptyShortcutGlyph
    }
}

private struct BrowserShortcutRecorderBridge: NSViewRepresentable {
    @Environment(\.locale) private var locale

    let identifier: String
    let title: String
    let shortcut: BrowserShortcut?
    let record: (BrowserShortcut?) -> Void
    let reportInvalidShortcut: () -> Void
    let onEndRecording: () -> Void

    func makeCoordinator() -> BrowserShortcutRecorderCoordinator {
        BrowserShortcutRecorderCoordinator(
            record: record,
            reportInvalidShortcut: reportInvalidShortcut,
            onEndRecording: onEndRecording
        )
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .monospacedSystemFont(
            ofSize: BrowserShortcutSettingsMetrics.recorderFontSize,
            weight: .medium
        )
        button.target = context.coordinator
        button.action = #selector(
            BrowserShortcutRecorderCoordinator.beginRecording(_:)
        )
        button.identifier = NSUserInterfaceItemIdentifier(
            BrowserShortcutSettingsAccessibilityID.recorderPrefix + identifier
        )
        button.recordingTitle = BrowserShortcutLocalization.string(
            BrowserShortcutSettingsPresentation.typeShortcut,
            locale: locale
        )
        button.eventHandler = context.coordinator.handle
        button.onEndRecording = context.coordinator.didEndRecording
        applyAccessibility(to: button)
        DispatchQueue.main.async { [weak button] in
            button?.beginRecording()
        }
        return button
    }

    func updateNSView(
        _ button: ShortcutRecorderButton,
        context: Context
    ) {
        context.coordinator.update(
            record: record,
            reportInvalidShortcut: reportInvalidShortcut,
            onEndRecording: onEndRecording
        )
        button.restingTitle =
            shortcut?.displayString(locale: locale)
            ?? BrowserShortcutSettingsPresentation.emptyShortcutGlyph
        button.recordingTitle = BrowserShortcutLocalization.string(
            BrowserShortcutSettingsPresentation.typeShortcut,
            locale: locale
        )
        button.eventHandler = context.coordinator.handle
        button.onEndRecording = context.coordinator.didEndRecording
        applyAccessibility(to: button)
    }

    private func applyAccessibility(to button: ShortcutRecorderButton) {
        button.setAccessibilityLabel(
            BrowserShortcutLocalization.string(
                BrowserShortcutSettingsPresentation.recorderAccessibilityLabel(title: title),
                locale: locale
            )
        )
        button.setAccessibilityValue(
            shortcut?.displayString(locale: locale)
                ?? BrowserShortcutLocalization.string(
                    BrowserShortcutSettingsPresentation.unassigned,
                    locale: locale
                )
        )
        let help = BrowserShortcutLocalization.string(
            BrowserShortcutSettingsPresentation.recorderHelp,
            locale: locale
        )
        button.setAccessibilityHelp(help)
        button.toolTip = help
    }
}

@MainActor
final class BrowserShortcutRecorderCoordinator: NSObject {
    private var record: (BrowserShortcut?) -> Void
    private var reportInvalidShortcut: () -> Void
    private var onEndRecording: () -> Void

    init(
        record: @escaping (BrowserShortcut?) -> Void,
        reportInvalidShortcut: @escaping () -> Void,
        onEndRecording: @escaping () -> Void
    ) {
        self.record = record
        self.reportInvalidShortcut = reportInvalidShortcut
        self.onEndRecording = onEndRecording
    }

    func update(
        record: @escaping (BrowserShortcut?) -> Void,
        reportInvalidShortcut: @escaping () -> Void,
        onEndRecording: @escaping () -> Void
    ) {
        self.record = record
        self.reportInvalidShortcut = reportInvalidShortcut
        self.onEndRecording = onEndRecording
    }

    @objc func beginRecording(_ sender: ShortcutRecorderButton) {
        sender.beginRecording()
    }

    func didEndRecording() {
        onEndRecording()
    }

    func handle(_ event: NSEvent, sender: ShortcutRecorderButton) {
        let modifiers = ShortcutModifiers(event.modifierFlags)
        if modifiers.isEmpty,
            let specialKey = ShortcutSpecialKey(keyCode: event.keyCode)
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
    var onEndRecording: (() -> Void)?

    private(set) var isRecording = false
    private var eventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = recordingTitle
        bezelColor = NSColor(CrestBrandTheme.accent)
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
        onEndRecording?()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            let wasRecording = isRecording
            isRecording = false
            title = restingTitle
            bezelColor = nil
            removeEventMonitor()
            if wasRecording { onEndRecording?() }
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
