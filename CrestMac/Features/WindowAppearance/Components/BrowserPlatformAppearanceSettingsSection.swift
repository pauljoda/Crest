import SwiftUI

/// The General pane's macOS-only sections: the window Crest draws itself, and the
/// Split View focus behaviour that only a pointer-driven shell has.
///
/// Mobile aliases this name to `EmptyView`, which makes it the seam where the
/// desktop contributes settings the phone and tablet have no equivalent for.
struct BrowserPlatformAppearanceSettingsSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue

    var body: some View {
        Section("Appearance") {
            Toggle("Animate Pages When Switching Spaces", isOn: $animatesSpacePages)
                .accessibilityIdentifier("animate-space-pages")
            CrestFormFootnote(
                "Move page cards with the sidebar when switching Spaces. Turn this off to show the destination page when it is ready, while keeping sidebar animations."
            )

            BrowserWindowTransparencyControls()

            CrestFormFootnote(
                "Only the Space atmosphere becomes translucent while the window is active. Web pages, text, and controls stay opaque; inactive windows return to opaque."
            )
            BrowserWindowTransparencySettingsPreview()
        }

        BrowserSplitFocusSettingsSection()
    }
}
