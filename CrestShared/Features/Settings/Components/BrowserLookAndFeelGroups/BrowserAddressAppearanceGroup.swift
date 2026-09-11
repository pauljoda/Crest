import SwiftUI

/// The address field's color, fill, and border, on every Space on this device.
struct BrowserAddressAppearanceGroup: View {
    var space: BrowserSpace?
    var showsPreview = false

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    var body: some View {
        CrestSettingsGroup("Address field", settings: settings) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .addressField)
            }
        } content: {
            BrowserAppearanceAccentRow(
                color: accent,
                fallback: space?.branding.primaryColor ?? .indigo,
                identifier: "address-follows-space-accent"
            )
            CrestSettingSlider("Color fill", value: fill, readout: .percent(zero: "None", full: "Strong"))
            CrestSettingSlider("Border", value: border, readout: .percent(zero: "None", full: "Strong"))
            CrestSettingRow(
                "Accent outline while editing",
                setting: outline.resettable("Accent outline while editing")
            ) {
                Toggle("Accent outline while editing", isOn: outline.binding)
                    .labelsHidden()
            }
        }
    }

    private var accent: CrestSettingValue<BrowserSpaceBrandColor?> {
        CrestSettingValue($appearance.address.color)
    }

    private var fill: CrestSettingValue<Double> {
        CrestSettingValue($appearance.address.fill, default: BrowserLookAndFeelDefaults.address.fill)
    }

    private var border: CrestSettingValue<Double> {
        CrestSettingValue($appearance.address.border, default: BrowserLookAndFeelDefaults.address.border)
    }

    private var outline: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.address.usesAccentWhenEditing,
            default: BrowserLookAndFeelDefaults.address.usesAccentWhenEditing)
    }

    private var settings: [CrestResettableSetting] {
        [
            accent.resettable("Follow Space accent"),
            fill.resettable("Color fill"),
            border.resettable("Border"),
            outline.resettable("Accent outline while editing"),
        ]
    }
}
