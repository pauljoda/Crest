import SwiftUI

/// How tabs show what their pages are doing, such as playing sound or being
/// shared, on every Space on this device.
struct BrowserTabStatusAppearanceGroup: View {
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter

    var body: some View {
        let settings = filter.settings(rows)
        if !settings.isEmpty {
            group(settings: settings)
        }
    }

    private func group(settings: [CrestResettableSetting]) -> some View {
        CrestSettingsGroup("Tab status", settings: settings) {
            CrestSettingRow("Status", setting: style.resettable("Status")) {
                Picker("Status", selection: style.binding) {
                    Text("Badge").tag(BrowserTabAppearance.StatusStyle.badge)
                    Text("Replace Icon").tag(BrowserTabAppearance.StatusStyle.icon)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Status")
            }
            .browserAppearanceSetting(.tabStatus)
            CrestSettingRow("Audio visualizer", setting: visualizer.resettable("Audio visualizer")) {
                Toggle("Audio visualizer", isOn: visualizer.binding)
                    .labelsHidden()
            }
            .browserAppearanceSetting(.audioVisualizer)
        }
    }

    private var style: CrestSettingValue<BrowserTabAppearance.StatusStyle> {
        CrestSettingValue($appearance.tabs.statusStyle, default: BrowserLookAndFeelDefaults.tabs.statusStyle)
    }

    private var visualizer: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.tabs.showsAudioVisualizer,
            default: BrowserLookAndFeelDefaults.tabs.showsAudioVisualizer)
    }

    private var rows: [(BrowserAppearanceSetting, CrestResettableSetting)] {
        [(.tabStatus, style.resettable("Status")), (.audioVisualizer, visualizer.resettable("Audio visualizer"))]
    }
}
