import SwiftUI

/// The one place every Look and Feel choice on this device goes back at once.
struct BrowserLookAndFeelResetFooter: View {
    /// What this shell puts back alongside the shared choices: window
    /// transparency and Space page motion on the desktop, the app icon on both.
    var resetPlatformChoices: () -> Void = {}

    @State private var confirmsReset = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: CrestSpacing.small) {
                Button("Reset All Look and Feel…") { confirmsReset = true }
                    .buttonStyle(.crestTertiary)
                    .accessibilityIdentifier("reset-look-and-feel")
                CrestFormFootnote("These settings apply to every Space on this device and don't sync.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .confirmationDialog(
                "Reset all Look and Feel settings?",
                isPresented: $confirmsReset,
                titleVisibility: .visible
            ) {
                Button("Reset All", role: .destructive, action: reset)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Window, tab, address field, folder, and app icon choices return to their defaults.")
            }
        }
    }

    private func reset() {
        BrowserLookAndFeelDefaults.resetAll()
        resetPlatformChoices()
    }
}
