import SwiftUI

struct BrowserDurableTabSettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore

    var body: some View {
        Section("Pinned and saved tabs") {
            closePicker("Pinned tabs after closing", selection: $preferences.pinnedTabClosePolicy)
                .accessibilityIdentifier("pinned-tab-close-policy")
            closePicker("Saved tabs after closing", selection: $preferences.savedTabClosePolicy)
                .accessibilityIdentifier("saved-tab-close-policy")
            if BrowserDeviceAppearanceStore.shared.customizationStyle.shows(.unloadedSavedTabs) {
                Toggle("Keep saved tabs after unloading", isOn: $preferences.unloadedSavedTabsStay)
                    .accessibilityIdentifier("saved-tab-unload-keeps-tab")
            }
            #if os(macOS)
                Toggle(
                    "Click the favicon to return to the saved URL", isOn: $preferences.returnsToSavedURLOnFaviconClick
                )
                .accessibilityIdentifier("saved-tab-favicon-root-return")
            #endif
        }
    }

    // MARK: - Actions - Building

    private func closePicker(_ title: LocalizedStringKey, selection: Binding<SavedTabClosePolicy>) -> some View {
        Picker(title, selection: selection) {
            ForEach(SavedTabClosePolicy.all, id: \.self) { policy in
                Text(policy.title).tag(policy)
            }
        }
    }
}
