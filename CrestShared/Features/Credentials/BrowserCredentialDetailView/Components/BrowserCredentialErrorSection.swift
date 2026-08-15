import SwiftUI

struct BrowserCredentialErrorSection: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Label(
                    message,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }
        }
    }
}

#Preview("Credential Error", traits: .sizeThatFitsLayout) {
    Form {
        BrowserCredentialErrorSection(
            message: "Crest couldn’t authenticate and read that password from this Space."
        )
    }
    .frame(width: 420)
}
