import SwiftUI

struct BrowserManualSetupErrorMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier(
                    BrowserManualSetupAccessibilityID.error
                )
        }
    }
}

#Preview("Manual Setup Error") {
    BrowserManualSetupErrorMessage(
        message: "That site could not be added."
    )
    .padding()
}
