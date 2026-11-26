import AppKit
import SwiftUI

struct BrowserShortcutList: View {
    let model: BrowserShortcutSettingsModel
    @Environment(\.browserSettingsTabState) private var tabState
    @Environment(\.locale) private var locale
    @State private var standaloneScroll = BrowserNativeScrollState()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.commandGroups) { group in
                    Section {
                        ForEach(group.commands) { command in
                            BrowserShortcutRow(
                                command: command,
                                shortcut: model.shortcut(for: command),
                                isCustomized: model.isCustomized(command),
                                preference: model.choosesPreference(command) ? model.preference(for: command) : nil,
                                locale: locale,
                                record: { model.record($0, for: command) },
                                choose: { model.choose($0, for: command) },
                                reset: { model.reset(command) },
                                reportInvalidShortcut: model.reportInvalidShortcut
                            )
                            .equatable()
                            if command.id != group.commands.last?.id {
                                Divider()
                                    .padding(.leading, CrestSpacing.medium)
                            }
                        }
                    } header: {
                        Text(group.section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, CrestSpacing.medium)
                            .padding(.top, CrestSpacing.medium)
                            .padding(.bottom, CrestSpacing.extraSmall)
                    }
                }
            }
            .padding(.bottom, CrestSpacing.medium)
        }
        .browserNativeScrollState(tabState?.scroll(for: .shortcuts) ?? standaloneScroll)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.commandGroups.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .accessibilityIdentifier(
            BrowserShortcutSettingsAccessibilityID.list
        )
    }
}

private struct BrowserShortcutRow: View, @MainActor Equatable {
    let command: ShortcutCommand
    let shortcut: BrowserShortcut?
    let isCustomized: Bool
    /// Who answers the keys while a focused page uses them too, or nil for a
    /// command that keeps its own.
    let preference: ShortcutPreference?
    let locale: Locale
    let record: (BrowserShortcut?) -> Void
    let choose: (ShortcutPreference) -> Void
    let reset: () -> Void
    let reportInvalidShortcut: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.command == rhs.command
            && lhs.shortcut == rhs.shortcut
            && lhs.isCustomized == rhs.isCustomized
            && lhs.preference == rhs.preference
            && lhs.locale == rhs.locale
    }

    var body: some View {
        HStack(spacing: BrowserShortcutSettingsMetrics.rowSpacing) {
            Text(command.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCustomized {
                Text(BrowserShortcutSettingsPresentation.custom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            BrowserShortcutRecorder(
                identifier: command.name,
                title: command.title(locale: locale),
                shortcut: shortcut,
                record: record,
                reportInvalidShortcut: reportInvalidShortcut
            )
            .frame(
                width: BrowserShortcutSettingsMetrics.recorderWidth,
                height: BrowserShortcutSettingsMetrics.recorderHeight
            )

            Button(action: presentActionsMenu) {
                Image(systemName: "ellipsis")
                    .frame(
                        width: BrowserShortcutSettingsMetrics.actionSize,
                        height: BrowserShortcutSettingsMetrics.actionSize
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
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
        .padding(.horizontal, CrestSpacing.medium)
        .padding(
            .vertical,
            BrowserShortcutSettingsMetrics.rowVerticalPadding + CrestSpacing.extraSmall
        )
        .accessibilityElement(children: .contain)
    }

    private func presentActionsMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let clearItem = ShortcutActionMenuItem(
            title: BrowserShortcutLocalization.string(
                BrowserShortcutSettingsPresentation.clearShortcut, locale: locale),
            symbol: "delete.left",
            isEnabled: shortcut != nil
        ) {
            record(nil)
        }
        menu.addItem(clearItem)

        let resetItem = ShortcutActionMenuItem(
            title: BrowserShortcutLocalization.string(
                BrowserShortcutSettingsPresentation.resetToDefault, locale: locale),
            symbol: "arrow.counterclockwise",
            isEnabled: isCustomized
        ) {
            reset()
        }
        menu.addItem(resetItem)

        if let preference {
            menu.addItem(.separator())
            let header = NSMenuItem.sectionHeader(
                title: BrowserShortcutLocalization.string(
                    BrowserShortcutSettingsPresentation.whenWebsiteUsesKeys, locale: locale)
            )
            menu.addItem(header)
            for option in ShortcutPreference.all {
                let item = ShortcutActionMenuItem(
                    title: BrowserShortcutLocalization.string(option.title, locale: locale),
                    symbol: option.symbol,
                    isEnabled: true
                ) {
                    choose(option)
                }
                if option == preference { item.state = .on }
                menu.addItem(item)
            }
        }

        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let location =
            NSApp.currentEvent.map { contentView.convert($0.locationInWindow, from: nil) }
            ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        menu.popUp(positioning: nil, at: location, in: contentView)
    }
}

@MainActor
private final class ShortcutActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, symbol: String, isEnabled: Bool, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
        self.isEnabled = isEnabled
        self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}
