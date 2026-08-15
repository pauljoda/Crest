import SwiftUI

struct BrowserShortcutRow: View {
    @Environment(\.locale) private var locale

    let command: BrowserShortcutCommand
    let shortcut: BrowserShortcut?
    let isCustomized: Bool
    let record: (BrowserShortcut?) -> Void
    let reset: () -> Void
    let reportInvalidShortcut: () -> Void

    var body: some View {
        HStack(spacing: BrowserShortcutSettingsMetrics.rowSpacing) {
            Text(command.titleResource)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCustomized {
                Text(BrowserShortcutSettingsPresentation.custom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            BrowserShortcutRecorder(
                identifier: command.rawValue,
                title: command.title(locale: locale),
                shortcut: shortcut,
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
                .disabled(shortcut == nil)
                Button(
                    BrowserShortcutSettingsPresentation.resetToDefault,
                    systemImage: "arrow.counterclockwise",
                    action: reset
                )
                .disabled(!isCustomized)
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
                        .actionsAccessibilityLabel(
                            title: command.title(locale: locale)
                        )
                )
            )
        }
        .padding(
            .vertical,
            BrowserShortcutSettingsMetrics.rowVerticalPadding
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview("Customized Crest Command") {
    BrowserShortcutRow(
        command: .newTab,
        shortcut: BrowserShortcut(
            key: .character("g"),
            modifiers: [.command, .option]
        ),
        isCustomized: true,
        record: { _ in },
        reset: {},
        reportInvalidShortcut: {}
    )
    .padding()
    .frame(width: BrowserShortcutSettingsMetrics.previewRowWidth)
}
