import SwiftUI

/// The General pane's macOS-only sections: the window Crest draws itself, and the
/// Split View focus behaviour that only a pointer-driven shell has.
///
/// Mobile aliases this name to `EmptyView`, which makes it the seam where the
/// desktop contributes settings the phone and tablet have no equivalent for.
struct BrowserPlatformAppearanceSettingsSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue

    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarOnRight = false
    @AppStorage(BrowserChromeAppearancePreference.borderlessKey, store: BrowserChromeAppearancePreference.defaults)
    private var borderless = false

    var body: some View {
        Section("Appearance") {
            Toggle("Borderless Window", isOn: $borderless)
                .accessibilityIdentifier("borderless-window")
            Toggle("Sidebar on Right", isOn: $sidebarOnRight)
                .accessibilityIdentifier("sidebar-on-right")
            CrestFormFootnote(
                "Apply to all browser windows. Borderless windows place web content directly beside the sidebar and at the window edges."
            )

            BrowserWindowTransparencySettingsPreview(
                appearance: BrowserChromeAppearance(sidebarOnRight: sidebarOnRight, borderless: borderless)
            )

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
