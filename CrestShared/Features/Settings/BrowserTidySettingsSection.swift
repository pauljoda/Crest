import SwiftUI

/// Whether the sidebar offers Tidy, which sorts open tabs into Groups by
/// topic on this device. Off by default, and can't be turned on where Apple
/// Intelligence is unavailable, though it can always be turned off, which
/// deletes its word list.
struct BrowserTidySettingsSection: View {
    @Bindable var tidying = TabTidying.shared

    var body: some View {
        Section {
            // Bound through Tidy, which stops its work the moment it is
            // turned off.
            Toggle("Offer Tidy for open tabs", isOn: $tidying.isOn)
                .disabled(!TabTidying.isModelAvailable && !tidying.isOn)
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
        if tidying.isOn, tidying.wordTable.isDownloading {
            return "Downloading Tidy’s word list…"
        }
        if tidying.isOn, tidying.wordTable.didFail {
            return "Couldn’t download Tidy’s word list. Turn Tidy off and on to try again."
        }
        return "Sorts open tabs into Groups by topic, on this device. Turning it on downloads a 30 MB word list."
    }
}
