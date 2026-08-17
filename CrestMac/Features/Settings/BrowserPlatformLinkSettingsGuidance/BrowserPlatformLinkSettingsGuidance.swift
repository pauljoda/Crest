import SwiftUI

struct BrowserPlatformLinkSettingsGuidance: View {
    let kind: BrowserLinkSettingsGuidanceKind
    var peekClickModifier: BrowserLinkClickModifier = .option

    @ViewBuilder
    var body: some View {
        switch kind {
        case .externalDestination:
            CrestFormFootnote(
                "Quick Window opens a transient page using the most recent Space’s cookies and Crest Passwords. Most Recent Space creates a current tab immediately."
            )
        case .quickWindow:
            Label(
                "Opening in another Space reloads the page inside that Space’s independent website-data store.",
                systemImage: "person.crop.circle.badge.checkmark"
            )
            .crestFormFootnote()
        case .peek:
            CrestFormFootnote(
                "\(peekClickModifier.clickTitle) opens any web link in Peek. Dismiss with Escape, ⌘W, the close button, or the outside area; ⌘O expands it into a current tab."
            )
        }
    }
}
