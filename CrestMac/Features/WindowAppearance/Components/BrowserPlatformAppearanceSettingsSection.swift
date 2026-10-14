import SwiftUI

/// The shared Window group, plus the window choice only the desktop has.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarRevealWidthPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
    @AppStorage(SidebarEdgeRestHidePreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarEdgeRestHideDelay = SidebarEdgeRestHidePreference.defaultValue

    var body: some View {
        let motion = CrestSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)

        let revealWidth = CrestSettingValue($sidebarRevealWidth, default: SidebarRevealWidthPreference.defaultValue)
        let edgeRestHide = CrestSettingValue(
            $sidebarEdgeRestHideDelay, default: SidebarEdgeRestHidePreference.defaultValue)

        return BrowserWindowAppearanceGroup(
            space: space,
            showsPreview: showsPreview,
            extraSettings: [
                motion.resettable("Animate pages when switching Spaces"),
                revealWidth.resettable("Sidebar hover area"),
                edgeRestHide.resettable("Hide sidebar when the pointer rests at the screen edge"),
            ]
        ) {
            CrestSettingRow(
                "Animate pages when switching Spaces",
                setting: motion.resettable("Animate pages when switching Spaces")
            ) {
                Toggle("Animate pages when switching Spaces", isOn: motion.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("animate-space-pages")
            }

            CrestSettingSlider(
                "Sidebar hover area",
                value: revealWidth,
                range: SidebarRevealWidthPreference.range,
                readout: .points,
                identifier: "sidebar-reveal-width",
                onEditingChanged: { _ in SidebarRevealWidthPreview.shared.adjusted() }
            )
            .onChange(of: sidebarRevealWidth) { SidebarRevealWidthPreview.shared.adjusted() }

            CrestSettingSlider(
                "Hide sidebar when the pointer rests at the screen edge",
                value: edgeRestHide,
                range: SidebarEdgeRestHidePreference.range,
                step: 1,
                readout: .seconds(zero: "Off"),
                identifier: "sidebar-edge-rest-hide-delay"
            )
        }
    }
}
