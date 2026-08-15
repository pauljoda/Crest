import AppKit
import SwiftUI

struct BrowserShortcutRecorder: NSViewRepresentable {
    @Environment(\.locale) private var locale

    let identifier: String
    let title: String
    let shortcut: BrowserShortcut?
    let record: (BrowserShortcut?) -> Void
    let reportInvalidShortcut: () -> Void

    func makeCoordinator() -> BrowserShortcutRecorderCoordinator {
        BrowserShortcutRecorderCoordinator(
            record: record,
            reportInvalidShortcut: reportInvalidShortcut
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
        return button
    }

    func updateNSView(
        _ button: ShortcutRecorderButton,
        context: Context
    ) {
        context.coordinator.update(
            record: record,
            reportInvalidShortcut: reportInvalidShortcut
        )
        button.restingTitle =
            shortcut?.displayString(locale: locale)
            ?? BrowserShortcutSettingsPresentation.emptyShortcutGlyph
        button.recordingTitle = BrowserShortcutLocalization.string(
            BrowserShortcutSettingsPresentation.typeShortcut,
            locale: locale
        )
        button.eventHandler = context.coordinator.handle
        button.setAccessibilityLabel(
            BrowserShortcutLocalization.string(
                BrowserShortcutSettingsPresentation
                    .recorderAccessibilityLabel(title: title),
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

#Preview("Shortcut Recorder") {
    BrowserShortcutRecorder(
        identifier: BrowserShortcutCommand.newTab.rawValue,
        title: BrowserShortcutCommand.newTab.title,
        shortcut: BrowserShortcutCommand.newTab.defaultShortcut,
        record: { _ in },
        reportInvalidShortcut: {}
    )
    .frame(
        width: BrowserShortcutSettingsMetrics.recorderWidth,
        height: BrowserShortcutSettingsMetrics.recorderHeight
    )
    .padding()
}
