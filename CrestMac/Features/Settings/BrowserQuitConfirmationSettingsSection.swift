import SwiftUI

/// The Mac's native quit prompt preference, shared with its dismissal action.
struct BrowserQuitConfirmationSettingsSection: View {
    // MARK: - Variables

    @AppStorage(BrowserMacQuit.suppressionKey) private var suppressConfirmation = false

    private var confirmsQuit: Binding<Bool> {
        Binding(
            get: { !suppressConfirmation },
            set: { suppressConfirmation = !$0 })
    }

    var body: some View {
        Section("Quitting") {
            Toggle("Confirm before quitting", isOn: confirmsQuit)
                .accessibilityIdentifier("confirm-before-quitting")
        }
    }
}
