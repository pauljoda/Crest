import SwiftUI

struct BrowserSiteExtensionActionLabel: View {
    let action: BrowserExtensionActionPresentation

    var body: some View {
        BrowserExtensionActionArtwork(
            action: action,
            glyphSize: BrowserSiteControlLayoutPolicy.extensionGlyphSize
        )
        .frame(maxWidth: .infinity)
        .frame(height: BrowserSiteControlLayoutPolicy.extensionActionHeight)
        .contentShape(.rect)
    }
}

#Preview("Site Extension Action Label") {
    BrowserSiteExtensionActionLabel(
        action: BrowserSidebarExtensionPreviewFixture.actions[0]
    )
    .padding()
    .frame(width: 72)
}
