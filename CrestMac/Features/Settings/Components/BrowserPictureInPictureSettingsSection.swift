import SwiftUI

struct BrowserPictureInPictureSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section("Video", systemImage: "pip") {
            Toggle("Automatically enter Picture in Picture", isOn: $preferences.automaticallyEntersPictureInPicture)
                .accessibilityIdentifier("automatic-picture-in-picture-toggle")
            CrestFormFootnote(
                "Keep playing videos visible when you switch tabs. Background videos are skipped, and an existing Picture in Picture session is never replaced."
            )
        }
    }
}
