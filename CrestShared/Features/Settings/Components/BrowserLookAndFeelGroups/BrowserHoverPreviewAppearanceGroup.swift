import SwiftUI

/// Which sidebar rows show a preview card when the pointer rests on them, or
/// a finger holds them, on this device, where the app's windows draw them.
struct BrowserHoverPreviewAppearanceGroup: View {
    // MARK: - Static Variables

    /// The section's name: on the Mac previews come from the pointer alone,
    /// and on an iPhone or iPad from holding a row too.
    private static var title: LocalizedStringKey {
        #if os(macOS)
            "Preview hover"
        #else
            "Previews"
        #endif
    }

    // MARK: - Variables

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter
    @Environment(\.browserHostsTabPreviews) private var hostsPreviews

    var body: some View {
        let settings = filter.settings(rows)
        if hostsPreviews, !settings.isEmpty {
            group(settings: settings)
        }
    }

    private func group(settings: [CrestResettableSetting]) -> some View {
        CrestSettingsGroup(Self.title, settings: settings) {
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
