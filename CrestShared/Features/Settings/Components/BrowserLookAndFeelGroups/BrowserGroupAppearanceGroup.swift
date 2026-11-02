import SwiftUI

/// How groups read in every Space on this device. By default a group shows
/// its name alone and lights up with its tabs on hover.
struct BrowserGroupAppearanceGroup: View {
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    var body: some View {
        CrestSettingsGroup("Groups", settings: settings) {
            CrestSettingRow("Tint Group Name", setting: titles.resettable("Tint Group Name")) {
                Toggle("Tint Group Name", isOn: titles.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-tint-title")
            }
            CrestSettingRow(
                "Always show group highlights", setting: highlights.resettable("Always show group highlights")
            ) {
                Toggle("Always show group highlights", isOn: highlights.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-always-show-highlights")
            }
            CrestSettingRow("Show group tab counts", setting: counts.resettable("Show group tab counts")) {
                Toggle("Show group tab counts", isOn: counts.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-show-tab-counts")
            }
            CrestSettingRow("Show group color borders", setting: borders.resettable("Show group color borders")) {
                Toggle("Show group color borders", isOn: borders.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("group-show-color-borders")
            }
        }
    }

    private var settings: [CrestResettableSetting] {
        [
            titles.resettable("Tint Group Name"),
            highlights.resettable("Always show group highlights"),
            counts.resettable("Show group tab counts"),
            borders.resettable("Show group color borders"),
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
