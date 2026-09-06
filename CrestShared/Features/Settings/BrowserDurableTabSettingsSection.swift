import SwiftUI

struct BrowserDurableTabSettingsSection: View {
    @Bindable var preferences: BrowserDurableTabPreferenceStore

    var body: some View {
        Section {
            Picker("After closing", selection: $preferences.closePolicy) {
                ForEach(BrowserDurableTabClosePolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .accessibilityIdentifier("durable-tab-close-policy")
            CrestFormFootnote(
                "Choose where pinned and saved tabs open after you close them. Switching Spaces or unloading inactive pages keeps your last location."
            )
        } header: {
            Text("Pinned and saved tabs")
        }
    }
}
