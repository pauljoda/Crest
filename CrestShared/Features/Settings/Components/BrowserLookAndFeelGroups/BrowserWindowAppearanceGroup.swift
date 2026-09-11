import SwiftUI

/// The window's frame: how much of the Space shows around a page, and which
/// side the sidebar sits on.
///
/// The desktop hands in the choices only it has — focused-window transparency
/// and Space page motion — as extra rows and the settings that go with them, so
/// the group's own Reset covers them too.
struct BrowserWindowAppearanceGroup<Extra: View>: View {
    var space: BrowserSpace?
    var showsPreview = false
    var extraSettings: [CrestResettableSetting] = []
    @ViewBuilder var extraRows: () -> Extra

    @AppStorage(BrowserChromeAppearancePreference.borderWidthKey, store: BrowserChromeAppearancePreference.defaults)
    private var borderWidth = BrowserLookAndFeelDefaults.windowBorderWidth
    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarOnRight = BrowserLookAndFeelDefaults.sidebarOnRight

    var body: some View {
        CrestSettingsGroup(
            "Window",
            settings: settings,
            footnote: "Borderless lets pages reach the window's edges."
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
            CrestSettingRow("Sidebar on right", setting: sidebar.resettable("Sidebar on right")) {
                Toggle("Sidebar on right", isOn: sidebar.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-on-right")
            }
            extraRows()
        }
    }

    private var border: CrestSettingValue<Double> {
        CrestSettingValue($borderWidth, default: BrowserLookAndFeelDefaults.windowBorderWidth)
    }

    private var sidebar: CrestSettingValue<Bool> {
        CrestSettingValue($sidebarOnRight, default: BrowserLookAndFeelDefaults.sidebarOnRight)
    }

    private var settings: [CrestResettableSetting] {
        [border.resettable("Window border"), sidebar.resettable("Sidebar on right")] + extraSettings
    }
}
