import SwiftUI

struct BrowserSpaceThemeField: View {
    let themeMode: BrowserSpaceThemeMode
    let bannerPattern: BrowserSpaceBannerPattern
    let gradientAngle: Double
    let colors: [Color]
    let size: CGSize

    @ViewBuilder
    var body: some View {
        switch themeMode {
        case .banner:
            BrowserSpaceBannerField(
                pattern: bannerPattern,
                colors: colors,
                size: size
            )
        case .gradient:
            BrowserSpaceGradientField(
                colors: colors,
                angle: gradientAngle
            )
        }
    }
}

#Preview("Theme Field — Gradient") {
    let branding = BrowserSpaceBrandingPreviewFixture.gradientBranding
    let size = CGSize(width: 320, height: 180)

    BrowserSpaceThemeField(
        themeMode: branding.themeMode,
        bannerPattern: branding.bannerPattern,
        gradientAngle: branding.gradientAngle,
        colors: branding.colors.map(\.color),
        size: size
    )
    .frame(width: size.width, height: size.height)
    .clipShape(.rect(cornerRadius: CrestRadius.card))
    .padding(CrestSpacing.large)
}
