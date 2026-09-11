import SwiftUI

struct BrowserChromeAppearanceSettingsControls: View {
    var atmosphereOpacity: Double = 1
    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarOnRight = false
    @AppStorage(BrowserChromeAppearancePreference.borderlessKey, store: BrowserChromeAppearancePreference.defaults)
    private var borderless = false

    var body: some View {
        Toggle("Borderless Window", isOn: $borderless)
            .accessibilityIdentifier("borderless-window")
        Toggle("Sidebar on Right", isOn: $sidebarOnRight)
            .accessibilityIdentifier("sidebar-on-right")
        CrestFormFootnote(
            "Applies to all browser windows. Borderless windows place web content directly beside the sidebar and at the window edges. The sidebar docks when there is room; swipe inward from its chosen edge to reveal it when hidden."
        )
        BrowserChromeAppearanceSettingsPreview(
            appearance: .init(sidebarOnRight: sidebarOnRight, borderless: borderless),
            atmosphereOpacity: atmosphereOpacity
        )
    }
}
