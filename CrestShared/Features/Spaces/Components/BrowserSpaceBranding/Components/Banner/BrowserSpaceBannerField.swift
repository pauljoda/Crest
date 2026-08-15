import SwiftUI

struct BrowserSpaceBannerField: View {
    let pattern: BrowserSpaceBannerPattern
    let colors: [Color]
    let size: CGSize

    @ViewBuilder
    var body: some View {
        let second = colors[min(1, colors.count - 1)]
        let third = colors[min(2, colors.count - 1)]

        switch pattern {
        case .solid:
            colors[0]
        case .split:
            HStack(spacing: 0) {
                colors[0]
                second
            }
        case .bands:
            VStack(spacing: 0) {
                colors[0]
                second
                third
            }
        case .diagonal:
            ZStack {
                colors[0]
                BrowserSpaceDiagonalMiddleBannerShape(size: size)
                    .fill(second)
                BrowserSpaceDiagonalLowerBannerShape(size: size)
                    .fill(third)
            }
        case .chevron:
            ZStack {
                colors[0]
                BrowserSpaceChevronMiddleBannerShape(size: size)
                    .fill(second)
                BrowserSpaceChevronLowerBannerShape(size: size)
                    .fill(third)
            }
        case .quartered:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    colors[0]
                    second
                }
                HStack(spacing: 0) {
                    third
                    colors[0]
                }
            }
        }
    }
}

#Preview("Banner Field — Diagonal") {
    let branding = BrowserSpaceBrandingPreviewFixture.bannerBranding
    let size = CGSize(width: 320, height: 180)

    BrowserSpaceBannerField(
        pattern: branding.bannerPattern,
        colors: branding.colors.map(\.color),
        size: size
    )
    .frame(width: size.width, height: size.height)
    .clipShape(.rect(cornerRadius: CrestRadius.card))
    .padding(CrestSpacing.large)
}
