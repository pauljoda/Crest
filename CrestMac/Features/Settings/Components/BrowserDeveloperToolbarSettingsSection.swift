import SwiftUI

struct BrowserDeveloperToolbarSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section {
            Picker("Developer toolbar", selection: $preferences.developerToolbar) {
                ForEach(DeveloperToolbarMode.all, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .accessibilityIdentifier("developer-toolbar-mode")
        } header: {
            Text("Developer")
        } footer: {
            CrestFormFootnote("Local pages are localhost, private network addresses, .local, .test and files.")
        }
    }
}
