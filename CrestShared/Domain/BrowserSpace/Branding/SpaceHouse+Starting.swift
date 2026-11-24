import Foundation

/// A house as the starting point of a Space's look: a template, which is a
/// full set of icon and colors, or a crest the Space wears as its icon in its
/// own colors.
extension SpaceHouse {
    /// The house a crest started from, by the name it recorded. Earlier builds
    /// recorded the house's English title, which differs only in case.
    static func startingPoint(of branding: SpaceBranding) -> SpaceHouse? {
        guard let recorded = branding.crest.startingPresetID else { return nil }
        return all.first { $0.name.caseInsensitiveCompare(recorded) == .orderedSame }
    }

    /// `branding` starting over from the house as a template: its colors,
    /// texture and sidebar, and its crest as the icon, as the core applies
    /// it. A core that cannot answer keeps the look as it is.
    func applying(to branding: SpaceBranding) -> SpaceBranding {
        (try? CrestCore.answer(ApplyHouse(branding: branding, house: self)))?.branding ?? branding
    }

    /// `branding` wearing the house's crest as its icon, in the Space's own
    /// colors, which stay as they are. A core that cannot answer keeps the
    /// look as it is.
    func wearingCrest(on branding: SpaceBranding) -> SpaceBranding {
        (try? CrestCore.answer(WearHouseCrest(branding: branding, house: self)))?.branding ?? branding
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
