using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Range rules for a Space's banner branding. The crest's heraldic vocabulary
/// stays with the native renderer; the core owns the palette size, the banner
/// strengths, the gradient angle, the crest's layer colors pointing at a color
/// that exists, its composition parameters within the ranges the renderer draws
/// and its custom figure, so the branding the core stages for sync is the one
/// every device renders.
public static class SpaceBrandingPolicy {
    #region Variables

    public const int MaximumColorCount = 3;
    public const int MaximumCrestPaletteCount = 4;
    /// The most letters a monogram figure shows.
    public const int MaximumMonogramLength = 2;

    /// The Space color used when a branding record has none.
    public static BrandColor DefaultColor { get; } = new(0.29, 0.25, 0.58);

    #endregion

    #region Actions - Normalization

    /// The branding with every rule the core owns applied: at most three colors
    /// and never none, strengths, fades and color components within 0 through 1,
    /// the gradient angle within a turn, and crest layers addressing a color that
    /// exists. The crest's own palette is dropped when it holds no color, its
    /// composition parameters stay within the ranges the renderer draws, and a
    /// custom figure that is the crest's own symbol is no custom figure.
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
                EdgeColorIndex = LayerIndex(crest.EdgeColorIndex, layers),
                Charge = Charge(crest.Charge, crest.Symbol),
                PlateScale = Measure(crest.PlateScale, 0.7, 1.15, 1),
                EdgeWidth = Measure(crest.EdgeWidth, 0, 1, 0),
                DivisionCount = Math.Clamp(crest.DivisionCount, 2, 8),
                OrdinaryWidth = Measure(crest.OrdinaryWidth, 0.5, 1.6, 1),
                TrimWeight = Measure(crest.TrimWeight, 0.5, 2, 1),
                TrimDetail = Math.Clamp(crest.TrimDetail, 6, 24),
                ChargeScale = Measure(crest.ChargeScale, 0.6, 1.5, 1),
                ChargeOffset = Measure(crest.ChargeOffset, -0.2, 0.2, 0),
                SheenAngle = Measure(crest.SheenAngle, 0, 360, 45),
                SealTeeth = Math.Clamp(crest.SealTeeth, 6, 24)
            }
        };
    }

    /// A crest's custom figure as the renderer draws it: names and letters
    /// trimmed, one emoji, a monogram of at most two capitals, nothing drawn in
    /// place of an empty one, and none at all when it is the crest's own symbol.
    public static CrestCharge? Charge(CrestCharge? charge, CrestSymbol symbol) {
        if (charge is null) return null;
        string text = charge.Text?.Trim() ?? "";
        var figure = charge.Kind switch {
            CrestChargeKind.System => text.Length == 0 ? new(CrestChargeKind.None) : charge with { Text = text },
            CrestChargeKind.Emoji => string.IsNullOrEmpty(charge.Text) ? new(CrestChargeKind.None)
                : charge with { Text = new System.Globalization.StringInfo(charge.Text).SubstringByTextElements(0, 1) },
            CrestChargeKind.Monogram => text.Length == 0 ? new(CrestChargeKind.None) : charge with {
                Text = FirstTextElements(text.ToUpperInvariant(), MaximumMonogramLength).ToUpperInvariant()
            },
            _ => charge
        };
        return figure.Kind == CrestChargeKind.Heraldic && figure.Symbol == symbol ? null : figure;
    }

    /// A composition parameter within `minimum` through `maximum`; one that is
    /// not a number takes `fallback`.
    private static double Measure(double value, double minimum, double maximum, double fallback) =>
        double.IsFinite(value) ? Math.Clamp(value, minimum, maximum) : fallback;

    private static string FirstTextElements(string text, int count) {
        var elements = new System.Globalization.StringInfo(text);
        return elements.LengthInTextElements <= count ? text : elements.SubstringByTextElements(0, count);
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
