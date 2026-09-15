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

#if DEBUG
    #Preview("Hidden and revealed") {
        VStack(spacing: 20) {
            BrowserCredentialPasswordValue(password: nil)
            BrowserCredentialPasswordValue(password: "sample-password-for-preview")
        }.padding().frame(width: 360)
    }
#endif
