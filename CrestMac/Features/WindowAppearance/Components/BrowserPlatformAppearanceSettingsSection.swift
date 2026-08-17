import SwiftUI

/// The General pane's macOS-only sections: the window Crest draws itself, and the
/// Split View focus behaviour that only a pointer-driven shell has.
///
/// Mobile aliases this name to `EmptyView`, which makes it the seam where the
/// desktop contributes settings the phone and tablet have no equivalent for.
struct BrowserPlatformAppearanceSettingsSection: View {
    var body: some View {
        Section("Appearance") {
            BrowserWindowTransparencyControls()

            CrestFormFootnote(
                "Only the Space atmosphere becomes translucent while the window is active. Web pages, text, and controls stay opaque; inactive windows return to opaque."
            )
        }

        BrowserSplitFocusSettingsSection()
    }
}
