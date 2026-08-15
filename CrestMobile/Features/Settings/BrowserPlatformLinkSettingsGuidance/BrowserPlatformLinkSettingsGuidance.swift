import SwiftUI

struct BrowserPlatformLinkSettingsGuidance: View {
    let kind: BrowserLinkSettingsGuidanceKind
    var peekClickModifier: BrowserLinkClickModifier = .option

    @ViewBuilder
    var body: some View {
        switch kind {
        case .externalDestination:
            CrestFormFootnote(
                "Quick Window keeps the link transient while using the most recent Space’s cookies and Crest Passwords. Most Recent Space creates a current tab immediately."
            )
        case .quickWindow, .peek:
            EmptyView()
        }
    }
}

#Preview("Link Settings Guidance") {
    Form {
        BrowserPlatformLinkSettingsGuidance(kind: .externalDestination)
    }
    .formStyle(.grouped)
}
