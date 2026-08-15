import SwiftUI

struct BrowserExtensionActionArtwork: View {
    let action: BrowserExtensionActionPresentation
    let glyphSize: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            artwork
                .frame(width: glyphSize, height: glyphSize)
            if !action.badgeText.isEmpty {
                BrowserExtensionBadge(text: action.badgeText)
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let icon = action.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "puzzlepiece.extension.fill")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Extension Action Artwork") {
    BrowserExtensionActionArtwork(
        action: BrowserSidebarExtensionPreviewFixture.actions[0],
        glyphSize: 20
    )
    .padding()
}
