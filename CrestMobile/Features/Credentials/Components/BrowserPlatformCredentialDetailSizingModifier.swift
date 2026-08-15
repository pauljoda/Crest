import SwiftUI

struct BrowserPlatformCredentialDetailSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

#Preview("Credential Detail Sizing") {
    Form {
        Text("Credential details")
    }
    .modifier(BrowserPlatformCredentialDetailSizingModifier())
}
