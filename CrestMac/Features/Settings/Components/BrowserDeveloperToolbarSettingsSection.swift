import SwiftUI

struct BrowserDeveloperToolbarSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section("Developer", systemImage: "hammer") {
            Toggle("Show developer toolbar on local pages", isOn: $preferences.automaticallyShowsDeveloperToolbar)
                .accessibilityIdentifier("automatic-developer-toolbar-toggle")
            CrestFormFootnote(
                "Opens the developer toolbar on localhost, private network addresses, local hosts such as .local and .test, and files. Shift-Command-I still shows or hides it on any page."
            )
        }
    }
}
