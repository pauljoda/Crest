import SwiftUI

struct MobileCredentialPromptError: View {
    let message: Text

    init(_ message: LocalizedStringKey) {
        self.message = Text(message)
    }

    init(verbatim message: String) {
        self.message = Text(verbatim: message)
    }

    var body: some View {
        message
            .font(.caption)
            .foregroundStyle(.red)
    }
}

#Preview("Credential Prompt Error") {
    MobileCredentialPromptError(
        "The form changed before Crest could fill the password."
    )
    .padding()
}
