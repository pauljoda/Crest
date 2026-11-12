import SwiftUI

/// The window's frame: how much of the Space shows around a page, which side
/// the sidebar sits on, and the accent its tabs and address field wear.
///
/// The desktop hands in the choices only it has — focused-window transparency
/// and Space page motion — as extra rows and the settings that go with them, so
/// the group's own Reset covers them too. The group shows the rows the page's
/// filter keeps, and none of itself when it keeps none.
struct BrowserWindowAppearanceGroup<Extra: View>: View {
    // MARK: - Variables

    var space: BrowserSpaceAppearance?
    var showsPreview = false
    var extraSettings: [(BrowserAppearanceSetting, CrestResettableSetting)] = []
    @ViewBuilder var extraRows: () -> Extra

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter

    // MARK: - Actions - Drawing

    var body: some View {
        let settings = filter.settings(rows)
        if !settings.isEmpty {
            group(settings: settings)
        }
    }

    private func group(settings: [CrestResettableSetting]) -> some View {
        CrestSettingsGroup(
            "Window",
            settings: settings
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .window)
            }
        } content: {
            CrestSettingSlider(
                "Window border",
                value: border,
                range: BrowserChromeAppearance.borderWidthRange,
                readout: .points(zero: "Borderless"),
                identifier: "window-border-width"
            )
            .browserAppearanceSetting(.windowBorder)
            CrestSettingSlider(
                "Material",
                value: material,
                range: 0...Double(CrestSurfaceMaterial.all.count - 1),
                step: 1,
                readout: CrestSettingSliderReadout {
                    String(localized: CrestSurfaceMaterial.at(position: Int($0.rounded())).title)
                },
                identifier: "surface-material"
            )
            .browserAppearanceSetting(.material)
            CrestSettingRow("Sidebar on right", setting: sidebar.resettable("Sidebar on right")) {
                Toggle("Sidebar on right", isOn: sidebar.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-on-right")
            }
            .browserAppearanceSetting(.sidebarOnRight)
            BrowserAppearanceAccentRow(
                color: accent,
                fallback: space?.branding.primaryColor ?? .indigo,
                identifier: "follows-space-accent"
            )
            .browserAppearanceSetting(.followSpaceAccent)
            extraRows()
        }
    }

    // MARK: - Actions - Settings

    private var border: CrestSettingValue<Double> {
        CrestSettingValue($appearance.windowBorderWidth, default: BrowserLookAndFeelDefaults.windowBorderWidth)
    }

    /// The sidebar's layer material, as a position from Ultra Thin to Ultra Thick.
    private var material: CrestSettingValue<Double> {
        CrestSettingValue(
            Binding(
                get: { Double(appearance.surfaceMaterial.position) },
                set: { appearance.surfaceMaterial = .at(position: Int($0.rounded())) }
            ),
            default: Double(BrowserLookAndFeelDefaults.surfaceMaterial.position)
        )
    }

    private var sidebar: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.sidebarOnRight, default: BrowserLookAndFeelDefaults.sidebarOnRight)
    }

    /// One accent for the selected tabs, pins and the address field, which
    /// keep their own stored colors.
    private var accent: CrestSettingValue<BrandColor?> {
        CrestSettingValue(
            Binding(
                get: { appearance.tabs.color ?? appearance.address.color },
                set: { color in
                    appearance.tabs.color = color
                    appearance.address.color = color
                }
            )
        )
    }

    private var rows: [(BrowserAppearanceSetting, CrestResettableSetting)] {
        [
            (.windowBorder, border.resettable("Window border")), (.material, material.resettable("Material")),
            (.sidebarOnRight, sidebar.resettable("Sidebar on right")),
            (.followSpaceAccent, accent.resettable("Follow Space accent")),
        ] + extraSettings
    }
}
