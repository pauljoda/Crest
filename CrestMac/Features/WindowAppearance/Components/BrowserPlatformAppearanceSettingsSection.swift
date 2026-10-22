import SwiftUI

/// The shared Window group, plus the window choice only the desktop has.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarRevealWidthPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
    @AppStorage(PictureInPictureMomentumPreference.key)
    private var pictureInPictureMomentumSpeed = PictureInPictureMomentumPreference.defaultValue.speed

    var body: some View {
        let motion = CrestSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)

        let revealWidth = CrestSettingValue($sidebarRevealWidth, default: SidebarRevealWidthPreference.defaultValue)

        let momentum = CrestSettingValue(
            Binding(
                get: { PictureInPictureMomentumPreference(storedSpeed: pictureInPictureMomentumSpeed) },
                set: { pictureInPictureMomentumSpeed = $0.speed }),
            default: PictureInPictureMomentumPreference.defaultValue)

        return BrowserWindowAppearanceGroup(
            space: space,
            showsPreview: showsPreview,
            extraSettings: [
                motion.resettable("Animate pages when switching Spaces"),
                revealWidth.resettable("Sidebar hover area"),
                momentum.resettable("Picture in Picture momentum"),
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

            CrestSettingRow(
                "Picture in Picture momentum",
                setting: momentum.resettable("Picture in Picture momentum")
            ) {
                Picker("Picture in Picture momentum", selection: momentum.binding) {
                    ForEach(PictureInPictureMomentumPreference.all) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("picture-in-picture-momentum")
            }
        }
    }
}
