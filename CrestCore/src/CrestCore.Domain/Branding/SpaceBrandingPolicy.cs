using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Range rules for a Space's banner branding. The crest's heraldic vocabulary
/// and its composition parameters stay with the native renderer; the core owns
/// the palette size, the banner strengths, the gradient angle and the crest's
/// layer colors pointing at a color that exists.
public static class SpaceBrandingPolicy {
    #region Variables

    public const int MaximumColorCount = 3;
    public const int MaximumCrestPaletteCount = 4;

    /// The Space color used when a branding record has none.
    public static BrandColor DefaultColor { get; } = new(0.29, 0.25, 0.58);

    #endregion

    #region Actions - Normalization

    /// The branding with every rule the core owns applied: at most three colors
    /// and never none, strengths, fades and color components within 0 through 1,
    /// the gradient angle within a turn, and crest layers addressing a color that
    /// exists. The crest's own palette is dropped when it holds no color.
    public static SpaceBranding Normalize(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        var colors = branding.Colors.Colors.Take(MaximumColorCount).Select(Color).ToArray();
        if (colors.Length == 0) colors = [DefaultColor];
        var palette = branding.Crest.Palette?.Colors.Take(MaximumCrestPaletteCount).Select(Color).ToArray();
        if (palette is { Length: 0 }) palette = null;
        int layers = LayerColorCount(palette?.Length, colors.Length);
        var crest = branding.Crest;
        return branding with {
            Colors = new(colors),
            BannerStrength = Unit(branding.BannerStrength),
            ReadabilityFade = Unit(branding.ReadabilityFade),
            GradientAngle = GradientAngle(branding.GradientAngle),
            FolderColorIntensity = Unit(branding.FolderColorIntensity),
            SymbolColor = branding.SymbolColor is { } symbol ? Color(symbol) : null,
            Crest = crest with {
                Palette = palette is null ? null : new(palette),
                BackplateColorIndex = LayerIndex(crest.BackplateColorIndex, layers),
                SecondaryFieldColorIndex = LayerIndex(crest.SecondaryFieldColorIndex, layers),
                OrdinaryColorIndex = LayerIndex(crest.OrdinaryColorIndex, layers),
                TrimColorIndex = LayerIndex(crest.TrimColorIndex, layers),
                SymbolColorIndex = LayerIndex(crest.SymbolColorIndex, layers),
                EdgeColorIndex = LayerIndex(crest.EdgeColorIndex, layers)
            }
        };
    }

    /// A strength, fade, intensity or color component, kept within 0 through 1.
    /// A value that is not a number falls back to `fallback`.
    public static double Unit(double value, double fallback = 0) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : fallback;

    /// Degrees in [0, 360).
    public static double GradientAngle(double angle) {
        if (!double.IsFinite(angle)) return 0;
        double remainder = angle % 360;
        return remainder >= 0 ? remainder : remainder + 360;
    }

    /// How many colors a crest's layer indices can address: its own palette
    /// when it has one, else the Space's colors, and never fewer than one.
    public static int LayerColorCount(int? crestPaletteCount, int spaceColorCount) =>
        Math.Max(crestPaletteCount ?? spaceColorCount, 1);

    /// A layer index outside the addressable colors falls back to the first.
    public static int LayerIndex(int index, int colorCount) => index >= 0 && index < colorCount ? index : 0;

    private static BrandColor Color(BrandColor color) =>
        new(Unit(color.Red), Unit(color.Green), Unit(color.Blue), Unit(color.Alpha, 1));

    #endregion
}
