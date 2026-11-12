import SwiftUI

/// The address field's fill, border, how much of the address it shows, how
/// it opens the command palette, and what copying its address copies, on
/// every Space on this device.
struct BrowserAddressAppearanceGroup: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false
    /// This device's link preferences, which keep Super Copy.
    var links: BrowserLinkPreferenceStore?

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter

    var body: some View {
        let settings = filter.settings(rows)
        if !settings.isEmpty {
            group(settings: settings)
        }
    }

    private func group(settings: [CrestResettableSetting]) -> some View {
        CrestSettingsGroup("Address field", settings: settings, footnote: footnote) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .addressField)
            }
        } content: {
            CrestSettingSlider("Color fill", value: fill, readout: .percent(zero: "None", full: "Strong"))
                .browserAppearanceSetting(.addressFill)
            CrestSettingSlider("Border", value: border, readout: .percent(zero: "None", full: "Strong"))
                .browserAppearanceSetting(.addressBorder)
            CrestSettingRow("Address", setting: display.resettable("Address")) {
                Picker("Address", selection: display.binding) {
                    Text("Two lines").tag(BrowserAddressAppearance.Display.twoLines)
                    Text("One line").tag(BrowserAddressAppearance.Display.oneLine)
                    Text("Site only").tag(BrowserAddressAppearance.Display.siteOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Address")
            }
            .browserAppearanceSetting(.addressDisplay)
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
            if let superCopy {
                CrestSettingRow("Super Copy", setting: superCopy.resettable("Super Copy")) {
                    Toggle("Super Copy", isOn: superCopy.binding)
                        .labelsHidden()
                }
                .browserAppearanceSetting(.superCopy)
            }
        }
    }

    /// What Super Copy does, while its row is on the page.
    private var footnote: LocalizedStringKey? {
        guard superCopy != nil, filter.shows(.superCopy) else { return nil }
        return
            "With Super Copy, copying or sharing a link leaves out its trackers, using AdGuard's URL Tracking filter. Copying the selected address keeps everything."
    }

    private var display: CrestSettingValue<BrowserAddressAppearance.Display> {
        CrestSettingValue($appearance.address.display, default: BrowserLookAndFeelDefaults.address.display)
    }

    /// Super Copy, on by default, kept with this device's link preferences.
    private var superCopy: CrestSettingValue<Bool>? {
        guard let links else { return nil }
        return CrestSettingValue(
            links.binding(.cleansCopiedLinks, reading: \.cleansCopiedLinks), default: true)
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
            (.addressDisplay, display.resettable("Address")),
            (.addressEditingOutline, outline.resettable("Accent outline while editing")),
            (.commandPaletteMotion, paletteMorph.resettable("Animate into command palette")),
        ]
        #if os(macOS)
            rows.append((.copyURLButton, copyURLButton.resettable("Copy URL button")))
        #endif
        if let superCopy { rows.append((.superCopy, superCopy.resettable("Super Copy"))) }
        return rows
    }
}
