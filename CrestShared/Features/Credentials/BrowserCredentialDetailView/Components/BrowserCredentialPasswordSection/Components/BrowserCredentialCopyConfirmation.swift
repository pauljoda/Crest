import SwiftUI

struct BrowserCredentialCopyConfirmation: View {
    let isPresented: Bool

    var body: some View {
        if isPresented {
            Label(
                "Copied locally for 60 seconds",
                systemImage: "checkmark.circle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Credential Copy Confirmation", traits: .sizeThatFitsLayout) {
    BrowserCredentialCopyConfirmation(isPresented: true)
        .padding()
}
