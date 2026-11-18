import SwiftUI

/// A Space's sidebar field: its banner, or its color as a gradient.
struct BrowserSpaceThemeField: View {
    let themeMode: SpaceThemeMode
    let bannerPattern: SpaceBannerPattern
    /// The sidebar's color, one or a gradient, which a gradient field wears.
    let sidebarFill: CrestColorFill
    /// The palette's colors as the banner fills them, each with its gradient.
    let fills: [AnyShapeStyle]
    let size: CGSize

    @ViewBuilder
    var body: some View {
        switch themeMode.kind {
        case .banner:
            BrowserSpaceBannerField(pattern: bannerPattern, fills: fills, size: size)
        case .gradient:
            BrowserSpaceGradientField(fill: sidebarFill)
        }
    }
}
