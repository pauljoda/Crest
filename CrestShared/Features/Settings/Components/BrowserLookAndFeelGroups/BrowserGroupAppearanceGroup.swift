import SwiftUI

/// How groups read in every Space on this device. By default a group shows
/// its name alone and lights up with its tabs on hover.
struct BrowserGroupAppearanceGroup: View {
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter

    var body: some View {
        let settings = filter.settings(rows)
        if !settings.isEmpty {
            group(settings: settings)
        }
    }

    private func group(settings: [CrestResettableSetting]) -> some View {
        CrestSettingsGroup("Groups", settings: settings) {
            CrestSettingRow("Tint Group Name", setting: titles.resettable("Tint Group Name")) {
                Toggle("Tint Group Name", isOn: titles.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-tint-title")
            }
            .browserAppearanceSetting(.groupTintTitle)
            CrestSettingRow(
                "Always show group highlights", setting: highlights.resettable("Always show group highlights")
            ) {
                Toggle("Always show group highlights", isOn: highlights.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-always-show-highlights")
            }
            .browserAppearanceSetting(.groupHighlights)
            CrestSettingRow("Show group tab counts", setting: counts.resettable("Show group tab counts")) {
                Toggle("Show group tab counts", isOn: counts.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-show-tab-counts")
            }
            .browserAppearanceSetting(.groupTabCounts)
            CrestSettingRow("Show group color borders", setting: borders.resettable("Show group color borders")) {
                Toggle("Show group color borders", isOn: borders.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-show-color-borders")
            }
            .browserAppearanceSetting(.groupBorders)
        }
    }

    private var rows: [(BrowserAppearanceSetting, CrestResettableSetting)] {
        [
            (.groupTintTitle, titles.resettable("Tint Group Name")),
            (.groupHighlights, highlights.resettable("Always show group highlights")),
            (.groupTabCounts, counts.resettable("Show group tab counts")),
            (.groupBorders, borders.resettable("Show group color borders")),
        ]
    }

    private var titles: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.groupsTintTitle, default: BrowserLookAndFeelDefaults.groupsTintTitle)
    }

    private var highlights: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.groupsAlwaysVisible, default: BrowserLookAndFeelDefaults.groupsAlwaysVisible)
    }

    private var counts: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.groupsShowTabCounts, default: BrowserLookAndFeelDefaults.groupsShowTabCounts)
    }

    private var borders: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.groupsShowBorders, default: BrowserLookAndFeelDefaults.groupsShowBorders)
    }
}
