import SwiftUI

/// Which sidebar rows show a preview card when the pointer rests on them, or
/// a finger holds them, on this device, where the app's windows draw them.
struct BrowserHoverPreviewAppearanceGroup: View {
    // MARK: - Variables

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter
    @Environment(\.browserTabPreviewHosting) private var hosting

    var body: some View {
        let settings = filter.settings(rows)
        if let hosting, !settings.isEmpty {
            group(hosting.settingsTitle, settings: settings)
        }
    }

    private func group(_ title: LocalizedStringKey, settings: [CrestResettableSetting]) -> some View {
        CrestSettingsGroup(title, settings: settings) {
            CrestSettingRow("Tabs", setting: tabs.resettable("Tabs")) {
                Toggle("Tabs", isOn: tabs.binding)
                    .labelsHidden()
            }
            .browserAppearanceSetting(.tabHoverPreview)
            CrestSettingRow("Folders", setting: folders.resettable("Folders")) {
                Toggle("Folders", isOn: folders.binding)
                    .labelsHidden()
            }
            .browserAppearanceSetting(.folderHoverPreview)
        }
    }

    private var tabs: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.previewsTabsOnHover, default: BrowserLookAndFeelDefaults.previewsTabsOnHover)
    }

    private var folders: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.previewsFoldersOnHover, default: BrowserLookAndFeelDefaults.previewsFoldersOnHover)
    }

    private var rows: [(BrowserAppearanceSetting, CrestResettableSetting)] {
        [(.tabHoverPreview, tabs.resettable("Tabs")), (.folderHoverPreview, folders.resettable("Folders"))]
    }
}
