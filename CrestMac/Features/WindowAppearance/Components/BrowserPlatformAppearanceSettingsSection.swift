import SwiftUI

/// The shared Window group, plus the window choices only the desktop has:
/// light or dark, how far dark dims Space colors, Space page motion, the
/// sidebar hover area, whether it stays live over a page in full screen, and
/// whether a Space shortcut shows a hidden sidebar for a moment.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue
    @AppStorage(SidebarSpaceShortcutRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarOnSpaceShortcut = SidebarSpaceShortcutRevealPreference.defaultValue

    var body: some View {
        let mode = CrestSettingValue($appearance.mode, default: BrowserLookAndFeelDefaults.appearanceMode)
        let dimming = CrestSettingValue(
            $appearance.darkSpaceDimming, default: BrowserLookAndFeelDefaults.darkSpaceDimming)

        let motion = CrestSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)

        let revealWidth = CrestSettingValue(
            $appearance.sidebarRevealWidth, default: SidebarRevealWidthPreference.defaultValue)
        let fullscreenReveal = CrestSettingValue(
            $revealsSidebarInFullscreen, default: SidebarFullscreenRevealPreference.defaultValue)
        let spaceShortcutReveal = CrestSettingValue(
            $revealsSidebarOnSpaceShortcut, default: SidebarSpaceShortcutRevealPreference.defaultValue)

        return BrowserWindowAppearanceGroup(
            space: space,
            showsPreview: showsPreview,
            extraSettings: [
                (.appearanceMode, mode.resettable("Appearance")),
                (.darkSpaceDimming, dimming.resettable("Dim Space colors in dark")),
                (.spacePageMotion, motion.resettable("Animate pages when switching Spaces")),
                (.sidebarRevealWidth, revealWidth.resettable("Sidebar hover area")),
                (.fullScreenSidebarReveal, fullscreenReveal.resettable("Show sidebar on hover in full screen")),
                (
                    .spaceShortcutSidebarReveal,
                    spaceShortcutReveal.resettable("Show sidebar when switching Spaces with shortcuts")
                ),
            ]
        ) {
            CrestSettingRow("Appearance", setting: mode.resettable("Appearance")) {
                Picker("Appearance", selection: mode.binding) {
                    ForEach(BrowserAppearanceMode.all, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("appearance-mode")
            }
            .browserAppearanceSetting(.appearanceMode)

            CrestSettingSlider(
                "Dim Space colors in dark",
                value: dimming,
                readout: .percent(zero: "Off", full: "Full"),
                identifier: "dark-space-dimming"
            )
            .browserAppearanceSetting(.darkSpaceDimming)

            CrestSettingRow(
                "Animate pages when switching Spaces",
                setting: motion.resettable("Animate pages when switching Spaces")
            ) {
                Toggle("Animate pages when switching Spaces", isOn: motion.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("animate-space-pages")
            }
            .browserAppearanceSetting(.spacePageMotion)

            CrestSettingSlider(
                "Sidebar hover area",
                value: revealWidth,
                range: SidebarRevealWidthPreference.range,
                readout: .points,
                identifier: "sidebar-reveal-width",
                onEditingChanged: { _ in SidebarRevealWidthPreview.shared.adjusted() }
            )
            .onChange(of: appearance.sidebarRevealWidth) { SidebarRevealWidthPreview.shared.adjusted() }
            .browserAppearanceSetting(.sidebarRevealWidth)

            CrestSettingRow(
                "Show sidebar on hover in full screen",
                setting: fullscreenReveal.resettable("Show sidebar on hover in full screen")
            ) {
                Toggle("Show sidebar on hover in full screen", isOn: fullscreenReveal.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-fullscreen-reveal")
            }
            .browserAppearanceSetting(.fullScreenSidebarReveal)

            CrestSettingRow(
                "Show sidebar when switching Spaces with shortcuts",
                setting: spaceShortcutReveal.resettable("Show sidebar when switching Spaces with shortcuts")
            ) {
                Toggle("Show sidebar when switching Spaces with shortcuts", isOn: spaceShortcutReveal.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-space-shortcut-reveal")
            }
            .browserAppearanceSetting(.spaceShortcutSidebarReveal)
        }
    }
}
