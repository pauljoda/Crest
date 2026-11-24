import SwiftUI

/// The password in Edit: the field itself, shown as it is, and a button that
/// puts a new strong one in it.
struct BrowserCredentialPasswordEditSection: View {
    @Binding var draft: BrowserCredentialDraft?
    /// Draws a new strong password, or nil when none can be made.
    let makePassword: () -> String?

    var body: some View {
        if let draft = $draft.editing {
            Section("Password") {
                HStack(spacing: CrestSpacing.small) {
                    TextField("Password", text: draft.password)
                        .font(.body.monospaced())
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("credential-password-field")
                    Button {
                        if let password = makePassword() { draft.wrappedValue.password = password }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(CrestChromeButtonStyle())
                    .help("Use Strong Password")
                    .accessibilityLabel("Use Strong Password")
                }
            }
        }
    }
}
