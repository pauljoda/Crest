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
