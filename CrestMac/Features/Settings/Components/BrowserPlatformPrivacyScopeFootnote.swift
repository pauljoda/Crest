import SwiftUI

struct BrowserPlatformPrivacyScopeFootnote: View {
    var body: some View {
        CrestFormFootnote(
            "Choices are stored separately for each exact site, port, capability, and Space. Camera and microphone access also require macOS privacy consent."
        )
    }
}

#Preview("Mac Privacy Scope", traits: .sizeThatFitsLayout) {
    BrowserPlatformPrivacyScopeFootnote()
        .padding()
}
