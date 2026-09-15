import SwiftUI

struct BrowserSpaceIdentityIcon: View {
    let space: BrowserSpace
    var size: CGFloat = 24

    var body: some View {
        Group {
            switch BrowserSpaceIdentityArtwork(space: space) {
            case .crest:
                BrowserSpaceCrestIcon(
                    branding: space.branding,
                    size: size
                )
            case .symbol(let systemImage):
                if let emoji = BrowserIconSymbol.emoji(from: systemImage) {
                    Text(emoji)
                        .font(.system(size: size * 0.68))
                        .frame(width: size, height: size)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.56, weight: .semibold))
                        .foregroundStyle(space.branding.resolvedSymbolColor.color)
                        .frame(width: size, height: size)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Symbol and locked crest") {
        HStack(spacing: 24) {
            BrowserSpaceIdentityIcon(space: BrowserSpaceBrandingPreviewFixture.simpleSpace, size: 32)
            BrowserSpaceIdentityIcon(space: BrowserSpaceBrandingPreviewFixture.crestSpace, size: 64)
        }.padding()
    }
#endif
