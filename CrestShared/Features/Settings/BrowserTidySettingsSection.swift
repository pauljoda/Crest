import SwiftUI

/// Whether the sidebar offers Tidy, which sorts open tabs into Groups by
/// topic on this device. Off by default, and can't be turned on where Apple
/// Intelligence is unavailable, though it can always be turned off, which
/// deletes its word list.
struct BrowserTidySettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore
    var tidying = TabTidying.shared

    var body: some View {
        Section {
            Toggle("Offer Tidy for open tabs", isOn: $preferences.offersTabTidying)
                .disabled(!TabTidying.isModelAvailable && !preferences.offersTabTidying)
                .accessibilityIdentifier("offer-tab-tidying-toggle")
        } header: {
            Text("Tidy")
        } footer: {
            CrestFormFootnote(footnote)
        }
    }

    private var footnote: LocalizedStringKey {
        guard #available(macOS 26, *) else { return "Requires macOS 26 or later." }
        guard TabTidying.isModelAvailable else { return "Requires Apple Intelligence." }
        if preferences.offersTabTidying, tidying.wordTable.isDownloading {
            return "Downloading Tidy’s word list…"
        }
        if preferences.offersTabTidying, tidying.wordTable.didFail {
            return "Couldn’t download Tidy’s word list. Turn Tidy off and on to try again."
        }
        return "Sorts open tabs into Groups by topic, on this device. Turning it on downloads a 30 MB word list."
    }
}
