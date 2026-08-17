import SwiftUI

struct BrowserShortcutList: View {
    let model: BrowserShortcutSettingsModel

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.commandGroups) { group in
                    Section {
                        ForEach(group.commands) { command in
                            BrowserShortcutRow(
                                command: command,
                                shortcut: model.shortcut(for: command),
                                isCustomized: model.isCustomized(command),
                                record: { model.record($0, for: command) },
                                reset: { model.reset(command) },
                                reportInvalidShortcut:
                                    model.reportInvalidShortcut
                            )
                        }
                    } header: {
                        Text(group.section.titleResource)
                    }
                }

                ForEach(model.extensionCommandGroups) { group in
                    Section {
                        ForEach(group.commands) { command in
                            BrowserExtensionShortcutRow(
                                command: command,
                                isRequested:
                                    model.scrollRequest?.targetID == command.id,
                                record: {
                                    model.record($0, for: command, in: group.spaceID)
                                },
                                reset: {
                                    model.reset(command, in: group.spaceID)
                                },
                                reportInvalidShortcut:
                                    model.reportInvalidShortcut
                            )
                            .id(command.id)
                        }
                    } header: {
                        Text(
                            BrowserShortcutSettingsPresentation.section(
                                extensionName: group.extensionName,
                                spaceName: group.spaceName
                            )
                        )
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if model.commandGroups.isEmpty
                    && model.extensionCommandGroups.isEmpty
                {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
            .onChange(of: model.scrollRequest, initial: true) {
                scroll(to: model.scrollRequest, using: proxy)
            }
            .accessibilityIdentifier(
                BrowserShortcutSettingsAccessibilityID.list
            )
        }
    }

    private func scroll(
        to request: BrowserShortcutScrollRequest?,
        using proxy: ScrollViewProxy
    ) {
        guard let request else { return }
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(request.targetID, anchor: .center)
        }
    }
}

private struct BrowserShortcutRow: View {
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

private struct BrowserExtensionShortcutRow: View {
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
