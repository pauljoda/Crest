import SwiftUI

struct BrowserPictureInPictureSettingsSection: View {
    @AppStorage(BrowserAutomaticPictureInPicturePreference.key)
    private var automaticallyEntersPictureInPicture = true

    var body: some View {
        Section("Video") {
            Toggle("Automatically enter Picture in Picture", isOn: $automaticallyEntersPictureInPicture)
                .accessibilityIdentifier("automatic-picture-in-picture-toggle")
            CrestFormFootnote(
                "Keep playing videos visible when you switch tabs. Background videos are skipped, and an existing Picture in Picture session is never replaced."
            )
        }
    }
}
