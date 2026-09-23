import SwiftUI

/// The Split View focus preference, in the General settings pane.
struct BrowserSplitFocusSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section("Split View", systemImage: "rectangle.split.2x1") {
            Toggle(
                "Focus Follows Mouse in Split View",
                isOn: $preferences.splitFocusFollowsMouse
            )

            CrestFormFootnote(
                "Moving the pointer over a card makes it the card the address bar, Find, and keyboard shortcuts speak for. Clicking a card always focuses it, whether or not this is on. Focus never moves while you are typing in the address bar."
            )
        }
    }
}
