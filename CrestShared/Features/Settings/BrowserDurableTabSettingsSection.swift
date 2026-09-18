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
            #if os(macOS)
                Toggle("Return to saved URL with one favicon click", isOn: $preferences.returnsToSavedURLOnFaviconClick)
                    .accessibilityIdentifier("saved-tab-favicon-root-return")
                CrestFormFootnote(
                    "When a saved tab shows /, click its favicon once to return to its saved URL. Double-clicking the tab still returns it."
                )
            #endif
        } header: {
            CrestSettingsSectionHeading(title: "Pinned and saved tabs", systemImage: "pin")
        }
    }
}
