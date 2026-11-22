namespace CrestCore.Contracts;

/// The look a Space an import brings wears: the branding it came with in
/// today's units and within the core's ranges, announcing the vocabulary it
/// draws with, or the legacy look of its accent and symbol when it came with
/// none.
public sealed partial record SpaceBranding {
    #region Static Variables

    /// The crest layers an imported composition addresses unless it chooses
    /// otherwise: the backplate, second field, ordinary, trim, figure and edge.
    private static readonly int[] ImportedLayers = [1, 1, 2, 1, 2, 1];

    /// The layers of an imported Space's own crest: the field and its edge in
    /// the crest's first color, the Space's own, and the figure in its second.
    private static readonly int[] OwnCrestLayers = [0, 0, 0, 0, 1, 0];

    /// How light a Space's color is, by its luminance, before its crest's
    /// figure turns from cream to ink.
    private const double LightFieldLuminance = 0.6;

    #endregion

    #region Actions - Imports

    /// `branding` as a Space keeps it, or the legacy look of `accent` and
    /// `symbol` when there is none.
    internal static SpaceBranding Kept(SpaceBranding? branding, SpaceAccent accent, string symbol) =>
        Normalized(branding ?? Legacy(accent, symbol));

    /// The neutral look a Space from another browser wears when it brought no
    /// colors, with the crest figure `symbol` suggests.
    internal static SpaceBranding NeutralImport(string symbol) =>
        Neutral with { Crest = Neutral.Crest with { Symbol = LegacyFigure(symbol) } };

    /// A look painted with another browser's `colors`, keeping controls
    /// readable unless `readabilityFade` says otherwise. Where the browser
    /// named the Space's icon, `symbol`, its crest is that icon raised off a
    /// round of the Space's first color, as the browser drew the Space;
    /// otherwise a plain mountain crest unless `figure` names another. An
    /// imported look keeps controls readable with `LegacyReadabilityFade`
    /// unless it names its own.
    internal static SpaceBranding Painted(IReadOnlyList<BrandColor> colors, SpaceBannerPattern pattern, double strength,
        double readabilityFade, SpaceThemeMode theme, double gradientAngle, double textureStrength, CrestSymbol? figure = null,
        string? symbol = null) {
        var crest = symbol is not null && colors.Count > 0 ? OwnCrest(colors[0], symbol)
            : SpaceCrest.PlainField(CrestBackplate.Shield, figure ?? CrestSymbol.Mountain, CrestTrim.None, ImportedLayers,
                trimWeight: 1, chargeScale: 1);
        return new(new(colors), pattern, strength, readabilityFade, readabilityFade > 0, theme, gradientAngle, textureStrength,
            SpaceIconStyle.SimpleSymbol, SymbolColor: null, crest, BaselineRenderingVersion, FolderColorIntensity: 0,
            SpaceTextColorMode.Automatic, HasCustomAppearance: null);
    }

    /// An imported Space's own crest: its icon `symbol`, an emoji or a system
    /// symbol, the symbol cream on a dark `field` and ink on a light one,
    /// raised off a plain round of `field`, in the simple style.
    private static SpaceCrest OwnCrest(BrandColor field, string symbol) {
        double luminance = 0.2126 * field.Red + 0.7152 * field.Green + 0.0722 * field.Blue;
        var figure = luminance > LightFieldLuminance ? Tincture.CrestInk.Color : Tincture.CrestCream.Color;
        return SpaceCrest.PlainField(CrestBackplate.Circle, CrestSymbol.Mountain, CrestTrim.None, OwnCrestLayers, trimWeight: 1,
            chargeScale: 1) with {
            Palette = new([field, figure]),
            Charge = EmojiIcon.Parse(symbol) is { } emoji
                ? new CrestCharge(CrestChargeKind.Emoji, Text: emoji.Emoji) : new CrestCharge(CrestChargeKind.System, Text: symbol),
            Depth = CrestDepth.Figure,
            EdgeWidth = 0
        };
    }

    #endregion
}
