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

#Preview("Shortcut List") {
    BrowserShortcutList(
        model: BrowserShortcutSettingsPreviewFactory.model()
    )
    .frame(
        width: BrowserShortcutSettingsMetrics.maximumContentWidth,
        height: 560
    )
}

#Preview("Empty Shortcut Search") {
    BrowserShortcutList(
        model: BrowserShortcutSettingsPreviewFactory.model(
            searchText: "no matching shortcut phrase"
        )
    )
    .frame(
        width: BrowserShortcutSettingsMetrics.maximumContentWidth,
        height: 320
    )
}
