import Foundation

/// A house as the starting point of a Space's look.
extension SpaceHouse {
    /// The house a crest started from, by the name it recorded. Earlier builds
    /// recorded the house's English title, which differs only in case.
    static func startingPoint(of branding: SpaceBranding) -> SpaceHouse? {
        guard let recorded = branding.crest.startingPresetID else { return nil }
        return all.first { $0.name.caseInsensitiveCompare(recorded) == .orderedSame }
    }

    /// `branding` starting over from the house's look and texture, keeping the
    /// Space's own strengths, folder and text choices. A look that started
    /// from a scheme wore the scheme's strength, fade, text and icon color
    /// rather than the person's, so it takes the house's own instead.
    func applying(to branding: SpaceBranding) -> SpaceBranding {
        var updated = branding
        if SpaceScheme.startingPoint(of: branding) != nil {
            updated.bannerStrength = look.bannerStrength
            updated.readabilityFade = look.readabilityFade
            updated.textColorMode = look.textColorMode
            updated.symbolColor = look.symbolColor
            updated.symbolGradient = look.symbolGradient
        }
        updated.colors = look.colors
        updated.colorGradients = look.colorGradients
        updated.textureStrength = look.textureStrength
        updated.themeMode = look.themeMode
        updated.bannerPattern = look.bannerPattern
        updated.gradientAngle = look.gradientAngle
        updated.gradientKind = look.gradientKind
        updated.iconStyle = .layeredCrest
        updated.crest = look.crest
        updated.crest.startingPresetID = name
        updated.hasCustomAppearance = false
        return updated.normalized()
    }

    /// Whether `branding` still wears the house's look unchanged.
    func isWorn(by branding: SpaceBranding) -> Bool {
        var crest = branding.crest
        crest.startingPresetID = nil
        return branding.hasCustomAppearance != true && branding.iconStyle == .layeredCrest
            && branding.colors == look.colors && branding.colorGradients == look.colorGradients
            && branding.themeMode == look.themeMode
            && (look.themeMode == .gradient || branding.bannerPattern == look.bannerPattern) && crest == look.crest
    }
}
