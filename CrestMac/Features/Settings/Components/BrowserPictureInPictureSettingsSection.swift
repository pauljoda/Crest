import SwiftUI

struct BrowserPictureInPictureSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section("Picture in Picture") {
            Toggle("When switching tabs", isOn: $preferences.automaticallyEntersPictureInPicture)
                .accessibilityIdentifier("automatic-picture-in-picture-toggle")
            Toggle("When switching apps", isOn: $preferences.floatsVideoOnAppSwitch)
            Toggle("When leaving Crest’s desktop", isOn: $preferences.floatsVideoOnDesktopSwitch)
            Toggle("Return video when its tab regains focus", isOn: $preferences.redocksVideoOnFocus)
        }
    }
}
