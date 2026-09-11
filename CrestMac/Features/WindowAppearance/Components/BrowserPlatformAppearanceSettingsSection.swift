import SwiftUI

/// The shared Window group, plus the two window choices only the desktop has.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpace?
    var showsPreview = false

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @Environment(BrowserWindowTransparencyStore.self) private var transparency

    var body: some View {
        @Bindable var transparency = transparency
        let isEnabled = CrestSettingValue(
            $transparency.isEnabled, default: BrowserWindowTransparencyPolicy.defaultEnabled)
        let strength = CrestSettingValue(
            $transparency.strength, default: BrowserWindowTransparencyPolicy.defaultStrength)
        let motion = CrestSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)

        return BrowserWindowAppearanceGroup(
            space: space,
            showsPreview: showsPreview,
            extraSettings: [
                isEnabled.resettable("Focused window transparency"),
                strength.resettable("Transparency"),
                motion.resettable("Animate pages when switching Spaces"),
            ]
        ) {
            CrestSettingRow(
                "Focused window transparency",
                setting: isEnabled.resettable("Focused window transparency")
            ) {
                Toggle("Focused window transparency", isOn: isEnabled.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("window-transparency-enabled")
            }
            CrestSettingSlider(
                "Transparency",
                value: strength,
                range: BrowserWindowTransparencyPolicy.strengthRange,
                readout: .percent,
                identifier: "window-transparency-strength"
            )
            .disabled(!isEnabled.wrappedValue)
            CrestSettingRow(
                "Animate pages when switching Spaces",
                setting: motion.resettable("Animate pages when switching Spaces")
            ) {
                Toggle("Animate pages when switching Spaces", isOn: motion.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("animate-space-pages")
            }
        }
    }
}
