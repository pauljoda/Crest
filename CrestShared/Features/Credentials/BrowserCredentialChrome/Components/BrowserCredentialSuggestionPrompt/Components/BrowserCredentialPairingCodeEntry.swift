import SwiftUI

/// Where the person types the code Apple Passwords shows in its own window.
struct BrowserCredentialPairingCodeEntry: View {
    let step: BrowserApplePasswordsPairingStep
    let feedback: BrowserApplePasswordsPairingOutcome?
    let submit: (String) -> Void
    let cancel: () -> Void

    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.savePromptContentSpacing) {
            TextField("6-digit code", text: $code)
                .crestTextField()
                .focused($isFocused)
                .disabled(step != .enteringCode)
                .onSubmit(pair)
            if let message = feedback?.message {
                BrowserCredentialPromptError(verbatim: String(localized: message))
            }
            HStack(spacing: BrowserCredentialPromptMetrics.saveActionSpacing) {
                Button("Cancel", action: cancel)
                    .buttonStyle(.crestSecondary)
                Spacer(minLength: 0)
                if step == .enteringCode {
                    Button("Pair", action: pair)
                        .buttonStyle(.crestPrimary)
                        .disabled(code.isEmpty)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: step) { _, step in
            if step == .enteringCode { isFocused = true }
        }
        .onChange(of: feedback) { _, feedback in
            // A spent code is not worth keeping in the field.
            if feedback?.asksForNewCode == true { code = "" }
        }
    }

    private func pair() {
        guard step == .enteringCode, !code.isEmpty else { return }
        submit(code)
    }
}
