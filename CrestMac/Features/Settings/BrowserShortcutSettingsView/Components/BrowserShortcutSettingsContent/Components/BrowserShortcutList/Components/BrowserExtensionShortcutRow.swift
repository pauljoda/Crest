import SwiftUI

struct BrowserExtensionShortcutRow: View {
    @Environment(\.locale) private var locale

    let command: BrowserShortcutExtensionCommand
    let isRequested: Bool
    let record: (BrowserShortcut?) -> Void
    let reset: () -> Void
    let reportInvalidShortcut: () -> Void

    var body: some View {
        HStack(spacing: BrowserShortcutSettingsMetrics.rowSpacing) {
            Text(command.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if command.isCustomized {
                Text(BrowserShortcutSettingsPresentation.custom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            BrowserShortcutRecorder(
                identifier: command.id.rawValue,
                title: BrowserShortcutLocalization.string(
                    BrowserShortcutSettingsPresentation
                        .extensionRecorderTitle(
                            extensionName: command.extensionDisplayName,
                            commandTitle: command.title
                        ),
                    locale: locale
                ),
                shortcut: command.shortcut,
                record: record,
                reportInvalidShortcut: reportInvalidShortcut
            )
            .frame(
                width: BrowserShortcutSettingsMetrics.recorderWidth,
                height: BrowserShortcutSettingsMetrics.recorderHeight
            )

            Menu {
                Button(
                    BrowserShortcutSettingsPresentation.clearShortcut,
                    systemImage: "delete.left"
                ) {
                    record(nil)
                }
                .disabled(command.shortcut == nil)
                Button(
                    BrowserShortcutSettingsPresentation
                        .resetToExtensionDefault,
                    systemImage: "arrow.counterclockwise",
                    action: reset
                )
                .disabled(!command.isCustomized)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(
                        width: BrowserShortcutSettingsMetrics.actionSize,
                        height: BrowserShortcutSettingsMetrics.actionSize
                    )
                    .contentShape(.rect)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(Text(BrowserShortcutSettingsPresentation.shortcutActions))
            .accessibilityLabel(
                Text(
                    BrowserShortcutSettingsPresentation
                        .actionsAccessibilityLabel(title: command.title)
                )
            )
        }
        .padding(
            .vertical,
            BrowserShortcutSettingsMetrics.rowVerticalPadding
        )
        .listRowBackground(
            isRequested
                ? Color.accentColor.opacity(
                    BrowserShortcutSettingsMetrics.requestedRowOpacity
                )
                : Color.clear
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview("Extension Command") {
    BrowserExtensionShortcutRow(
        command: BrowserShortcutExtensionCommand(
            extensionID: "preview.reader",
            extensionDisplayName: "Reader Tools",
            commandID: "capture",
            title: "Capture Article",
            shortcut: BrowserShortcut(
                key: .character("c"),
                modifiers: [.command, .option]
            ),
            isCustomized: true
        ),
        isRequested: true,
        record: { _ in },
        reset: {},
        reportInvalidShortcut: {}
    )
    .padding()
    .frame(width: BrowserShortcutSettingsMetrics.previewRowWidth)
}
