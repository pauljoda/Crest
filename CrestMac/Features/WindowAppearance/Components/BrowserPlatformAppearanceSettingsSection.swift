import SwiftUI

/// The General pane's macOS-only sections: the window Crest draws itself, and the
/// Split View focus behaviour that only a pointer-driven shell has.
///
/// Both platforms share the appearance controls; Mac adds window transparency.
struct BrowserPlatformAppearanceSettingsSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue

    @Environment(BrowserWindowTransparencyStore.self) private var transparency

    var body: some View {
        Section("Appearance") {
            BrowserChromeAppearanceSettingsControls(
                atmosphereOpacity: BrowserWindowTransparencyPolicy.baseLayerOpacity(
                    isEnabled: transparency.isEnabled, strength: transparency.strength, isWindowFocused: true))

            Toggle("Animate Pages When Switching Spaces", isOn: $animatesSpacePages)
                .accessibilityIdentifier("animate-space-pages")
            CrestFormFootnote(
                "Move page cards with the sidebar when switching Spaces. Turn this off to show the destination page when it is ready, while keeping sidebar animations."
            )

            BrowserWindowTransparencyControls()

            CrestFormFootnote(
                "Only the Space atmosphere becomes translucent while the window is active. Web pages, text, and controls stay opaque; inactive windows return to opaque."
            )

        }

        BrowserSplitFocusSettingsSection()
    }
}
