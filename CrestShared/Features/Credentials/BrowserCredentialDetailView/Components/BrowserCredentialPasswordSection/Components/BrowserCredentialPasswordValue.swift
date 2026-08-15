import SwiftUI

struct BrowserCredentialPasswordValue: View {
    let password: String?

    var body: some View {
        if let password {
            Text(password)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .accessibilityLabel("Password visible")
        } else {
            Text("••••••••••••")
                .font(.body.monospaced())
                .lineLimit(1)
                .accessibilityLabel("Password hidden")
        }
    }
}

#Preview("Credential Password Values", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
        BrowserCredentialPasswordValue(password: nil)
        BrowserCredentialPasswordValue(
            password: "correct-horse-battery-staple"
        )
    }
    .padding()
}
