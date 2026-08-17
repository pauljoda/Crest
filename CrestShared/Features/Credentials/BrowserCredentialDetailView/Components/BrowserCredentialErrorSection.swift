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
