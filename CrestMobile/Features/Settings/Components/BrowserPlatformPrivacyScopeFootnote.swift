import SwiftUI

struct BrowserPlatformPrivacyScopeFootnote: View {
    var body: some View {
        CrestFormFootnote(
            "Every exact site, port, capability, and Space has its own choice. Camera and microphone access also require device-level privacy consent."
        )
    }
}

#Preview("Mobile Privacy Scope", traits: .sizeThatFitsLayout) {
    BrowserPlatformPrivacyScopeFootnote()
        .padding()
}
