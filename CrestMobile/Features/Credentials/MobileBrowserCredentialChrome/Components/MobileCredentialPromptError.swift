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
