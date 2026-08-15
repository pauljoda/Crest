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

#Preview("Identity Icons") {
    HStack(spacing: CrestSpacing.large) {
        BrowserSpaceIdentityIcon(
            space: BrowserSpaceBrandingPreviewFixture.simpleSpace,
            size: 52
        )
        BrowserSpaceIdentityIcon(
            space: BrowserSpaceBrandingPreviewFixture.crestSpace,
            size: 52
        )
    }
    .padding(CrestSpacing.large)
    .frame(width: 180, height: 96)
}
