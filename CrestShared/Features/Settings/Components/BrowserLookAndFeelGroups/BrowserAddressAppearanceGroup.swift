import SwiftUI

/// The address field's fill, border, and how it opens the command palette,
/// on every Space on this device.
struct BrowserAddressAppearanceGroup: View {
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
        CrestSettingsGroup("Address field", settings: settings) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .addressField)
            }
        } content: {
            CrestSettingSlider("Color fill", value: fill, readout: .percent(zero: "None", full: "Strong"))
                .browserAppearanceSetting(.addressFill)
            CrestSettingSlider("Border", value: border, readout: .percent(zero: "None", full: "Strong"))
                .browserAppearanceSetting(.addressBorder)
            CrestSettingRow(
                "Accent outline while editing",
                setting: outline.resettable("Accent outline while editing")
            ) {
                Toggle("Accent outline while editing", isOn: outline.binding)
                    .labelsHidden()
            }
            .browserAppearanceSetting(.addressEditingOutline)
            CrestSettingRow(
                "Animate into command palette",
                setting: paletteMorph.resettable("Animate into command palette")
            ) {
                Toggle("Animate into command palette", isOn: paletteMorph.binding)
                    .labelsHidden()
            }
            .browserAppearanceSetting(.commandPaletteMotion)
            #if os(macOS)
                CrestSettingRow("Copy URL button", setting: copyURLButton.resettable("Copy URL button")) {
                    Toggle("Copy URL button", isOn: copyURLButton.binding)
                        .labelsHidden()
                }
                .browserAppearanceSetting(.copyURLButton)
            #endif
        }
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

    private var paletteMorph: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.address.animatesIntoCommandPalette,
            default: BrowserLookAndFeelDefaults.address.animatesIntoCommandPalette)
    }

    private var copyURLButton: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.address.showsCopyURLButton,
            default: BrowserLookAndFeelDefaults.address.showsCopyURLButton)
    }

    private var rows: [(BrowserAppearanceSetting, CrestResettableSetting)] {
        var rows: [(BrowserAppearanceSetting, CrestResettableSetting)] = [
            (.addressFill, fill.resettable("Color fill")),
            (.addressBorder, border.resettable("Border")),
            (.addressEditingOutline, outline.resettable("Accent outline while editing")),
            (.commandPaletteMotion, paletteMorph.resettable("Animate into command palette")),
        ]
        #if os(macOS)
            rows.append((.copyURLButton, copyURLButton.resettable("Copy URL button")))
        #endif
        return rows
    }
}
