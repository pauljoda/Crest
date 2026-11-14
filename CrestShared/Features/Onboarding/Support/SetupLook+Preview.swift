import SwiftUI

/// What a look shows of itself before any Space wears it: a template's look
/// in the look's own sidebar mode and icon style, as the core gives them to
/// the Spaces setup makes.
extension SetupLook {
    // MARK: - Static Variables

    /// The template every look's preview starts from.
    private static let previewHouse = SpaceHouse.winter

    // MARK: - Variables

    /// The look on the template every preview starts from.
    var previewBranding: SpaceBranding { applying(to: Self.previewHouse.look) }

    /// The symbol a previewed Space wears, which an icon shows and a crest
    /// keeps for the places too small for it.
    var previewSymbol: String { "house.fill" }

    // MARK: - Actions - Looks

    /// `branding` in this look: the sidebar mode, gradient angle and icon
    /// style the core gives the look, keeping its colors, crest and texture.
    /// A tinted look keeps only the accent color, at the look's strength,
    /// which the icon wears too.
    func applying(to branding: SpaceBranding) -> SpaceBranding {
        var look = branding
        look.themeMode = themeMode
        look.gradientAngle = gradientAngle ?? branding.gradientAngle
        look.iconStyle = iconStyle
        if let tint {
            let colors = branding.colors.colors
            let accent =
                colors.filter { (0.3...0.75).contains($0.lightness) }.max { $0.chroma < $1.chroma }
                ?? colors.first ?? SpaceBranding.neutral.colors.colors[0]
            look.colors = ColorPalette(colors: [accent])
            look.bannerStrength = tint
            look.readabilityFade = 0
            look.keepsControlsReadable = false
            look.symbolColor = accent.contrasting
            look.textColorMode = .automatic
        }
        return look.normalized()
    }
}

extension BrandColor {
    /// How light the color is, from 0 for black to 1 for white, as the core
    /// measures it when a tinted look picks a Space's color.
    fileprivate var lightness: Double { (max(red, green, blue) + min(red, green, blue)) / 2 }

    /// How far the color is from gray.
    fileprivate var chroma: Double { max(red, green, blue) - min(red, green, blue) }

    /// The shade an icon wears over this color, as the core makes it: deeper
    /// where dark text reads better on it, paler where light text does.
    fileprivate var contrasting: BrandColor {
        let toward = foregroundTone == .dark ? 0.0 : 1.0
        func mix(_ channel: Double) -> Double { channel + (toward - channel) * 0.55 }
        return BrandColor(red: mix(red), green: mix(green), blue: mix(blue), alpha: alpha)
    }
}
