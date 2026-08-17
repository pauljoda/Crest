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
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(space.branding.primaryColor.color)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}
