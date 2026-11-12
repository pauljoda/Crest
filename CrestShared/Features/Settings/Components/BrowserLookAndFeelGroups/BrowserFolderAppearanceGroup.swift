import SwiftUI

/// How folders read in every Space on this device. A Space's own folder color
/// travels with its branding and stays in the Space editor.
struct BrowserFolderAppearanceGroup: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter

    var body: some View {
        let settings = filter.settings(rows)
        if !settings.isEmpty {
            group(settings: settings)
        }
    }

    private func group(settings: [CrestResettableSetting]) -> some View {
        CrestSettingsGroup(
            "Folders",
            settings: settings
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .folders)
            }
        } content: {
            CrestSettingRow("Icon Only Folders", setting: icons.resettable("Icon Only Folders")) {
                Toggle("Icon Only Folders", isOn: icons.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-icon-only")
                    .help("Show a static custom icon or emoji instead of folder artwork.")
            }
            .browserAppearanceSetting(.folderIconOnly)
            CrestSettingRow("Tint Folder Title", setting: titles.resettable("Tint Folder Title")) {
                Toggle("Tint Folder Title", isOn: titles.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-tint-title")
            }
            .browserAppearanceSetting(.folderTintTitle)
            CrestSettingRow(
                "Always show folder highlights", setting: highlights.resettable("Always show folder highlights")
            ) {
                Toggle("Always show folder highlights", isOn: highlights.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-always-show-highlights")
            }
            .browserAppearanceSetting(.folderHighlights)
            CrestSettingRow("Show folder tab counts", setting: counts.resettable("Show folder tab counts")) {
                Toggle("Show folder tab counts", isOn: counts.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-show-tab-counts")
            }
            .browserAppearanceSetting(.folderTabCounts)
            CrestSettingRow("Show folder color borders", setting: borders.resettable("Show folder color borders")) {
                Toggle("Show folder color borders", isOn: borders.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-show-color-borders")
            }
            .browserAppearanceSetting(.folderBorders)
        }
    }

    private var highlights: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.foldersAlwaysVisible, default: BrowserLookAndFeelDefaults.foldersAlwaysVisible)
    }

    private var counts: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.foldersShowTabCounts, default: BrowserLookAndFeelDefaults.foldersShowTabCounts)
    }

    private var borders: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.foldersShowBorders, default: BrowserLookAndFeelDefaults.foldersShowBorders)
    }

    private var rows: [(BrowserAppearanceSetting, CrestResettableSetting)] {
        [
            (.folderIconOnly, icons.resettable("Icon Only Folders")),
            (.folderTintTitle, titles.resettable("Tint Folder Title")),
            (.folderHighlights, highlights.resettable("Always show folder highlights")),
            (.folderTabCounts, counts.resettable("Show folder tab counts")),
            (.folderBorders, borders.resettable("Show folder color borders")),
        ]
    }

    private var icons: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.foldersIconOnly, default: BrowserLookAndFeelDefaults.foldersIconOnly)
    }

    private var titles: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.foldersTintTitle, default: BrowserLookAndFeelDefaults.foldersTintTitle)
    }
}
