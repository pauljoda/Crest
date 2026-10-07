using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The look a Space an import brings wears: the branding it came with in
/// today's units and within the core's ranges, announcing the vocabulary it
/// draws with, or the legacy look of its accent and symbol when it came with
/// none.
internal static class ImportedLook {
    #region Static Variables

    /// The fade a look keeps controls readable with unless it names its own.
    public const double ReadableFade = SpaceBranding.LegacyReadabilityFade;

    /// The crest layers a composition addresses unless it chooses otherwise:
    /// the backplate, second field, ordinary, trim, figure and edge.
    private static readonly int[] DefaultLayers = [1, 1, 2, 1, 2, 1];

    #endregion

    #region Actions - Looks

    /// `branding` as a Space keeps it, or the legacy look of `accent` and
    /// `symbol` when there is none.
    public static SpaceBranding Kept(SpaceBranding? branding, SpaceAccent accent, string symbol) =>
        SpaceBrandingPolicy.Normalize(branding ?? SpaceBranding.Legacy(accent, symbol));

    /// The neutral look a Space from another browser wears when it brought no
    /// colors, with the crest figure `symbol` suggests.
    public static SpaceBranding Neutral(string symbol) =>
        SpaceBranding.Neutral with { Crest = SpaceBranding.Neutral.Crest with { Symbol = SpaceBranding.LegacyFigure(symbol) } };

    /// A look painted with another browser's `colors`, keeping controls
    /// readable unless `readabilityFade` says otherwise, with a plain mountain
    /// crest unless `figure` names another.
    public static SpaceBranding Painted(IReadOnlyList<BrandColor> colors, SpaceBannerPattern pattern, double strength,
        double readabilityFade, SpaceThemeMode theme, double gradientAngle, bool showsTexture, CrestSymbol? figure = null) {
        var crest = SpaceCrest.PlainField(CrestBackplate.Shield, figure ?? CrestSymbol.Mountain, CrestTrim.None, DefaultLayers,
            trimWeight: 1, chargeScale: 1);
        return new(new(colors), pattern, strength, readabilityFade, readabilityFade > 0, theme, gradientAngle, showsTexture,
            SpaceIconStyle.SimpleSymbol, SymbolColor: null, crest, SpaceBranding.BaselineRenderingVersion, FolderColorIntensity: 0,
            SpaceTextColorMode.Automatic, HasCustomAppearance: null);
    }

    #endregion
}
