import Foundation

/// The colors a Space's look draws with, by the part each plays, and the
/// core's branding rules applied to a look being edited.
extension SpaceBranding {
    // MARK: - Static Variables

    /// The most colors a Space's banner holds, as the core enforces it.
    static var maximumColorCount: Int { CapacityLimits.current.brandColors }

    // MARK: - Variables

    var backgroundColor: BrandColor {
        color(for: .background) ?? .indigo
    }

    var primaryColor: BrandColor {
        color(for: .accent) ?? backgroundColor
    }

    var secondaryColor: BrandColor {
        color(for: .pattern) ?? primaryColor
    }

    /// The icon's own color, or the Space's primary color, which it follows
    /// as the palette changes, when it has none.
    var resolvedSymbolColor: BrandColor {
        symbolColor ?? primaryColor
    }

    // MARK: - Actions - Text

    /// The tone that reads best over the colors the sidebar paints, unless
    /// the text color mode names one or follows the device, whose appearance
    /// reads in `system`.
    func foregroundTone(system: BrowserSpaceForegroundTone) -> BrowserSpaceForegroundTone {
        if let override = textColorMode.foregroundTone(system: system) { return override }
        let painted = paintedColors
        return ColorPalette(colors: painted.isEmpty ? [.indigo] : painted).foregroundTone(
            strength: bannerStrength, readabilityFade: readabilityFade, system: system)
    }

    /// The colors the sidebar paints: a solid sidebar its Background and the
    /// colors its gradient runs into, a pattern every color and the colors
    /// each runs into, and a sidebar that draws its colors as one gradient
    /// those colors. A Space's Accent, which only its crest and highlights
    /// wear on a solid sidebar, has no say in the sidebar's text.
    var paintedColors: [BrandColor] {
        if themeMode == .gradient { return Array(colors) }
        if bannerPattern == .solid { return backgroundFill.colors }
        return colors.indices.flatMap { slotFill($0).colors }
    }

    // MARK: - Actions - Colors

    func color(for role: BrowserSpaceBrandColorRole) -> BrandColor? {
        colors.indices.contains(role.slot) ? colors[role.slot] : nil
    }

    // MARK: - Actions - Normalizing

    /// This look with the core's branding rules applied, announcing the
    /// readability and rendering vocabulary it needs, as a Space keeps it. A
    /// core that cannot answer keeps the look as it is.
    func normalized() -> SpaceBranding {
        (try? CrestCore.answer(NormalizeBranding(branding: self)))?.branding ?? self
    }
}
