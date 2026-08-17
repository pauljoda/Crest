import SwiftUI

/// The Split View focus preference, in the General settings pane.
struct BrowserSplitFocusSettingsSection: View {
    @Environment(BrowserSplitFocusPreferenceStore.self) private var splitFocus

    var body: some View {
        @Bindable var splitFocus = splitFocus
        Section("Split View") {
            Toggle(
                "Focus Follows Mouse in Split View",
                isOn: $splitFocus.followsMouse
            )

            CrestFormFootnote(
                "Moving the pointer over a card makes it the card the address bar, Find, and keyboard shortcuts speak for. Clicking a card always focuses it, whether or not this is on. Focus never moves while you are typing in the address bar."
            )
        }
    }
}
