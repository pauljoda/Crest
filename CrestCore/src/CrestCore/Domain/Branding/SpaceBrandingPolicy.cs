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
    public const int MaximumCrestPaletteCount = 6;
    /// The most letters a monogram figure shows.
    public const int MaximumMonogramLength = 2;

    /// The Space color used when a branding record has none.
    public static BrandColor DefaultColor { get; } = new(0.29, 0.25, 0.58);

    #endregion

    #region Actions - Normalization

    /// The branding with every rule the core owns applied, as every client
    /// writes it: its banner strength in today's units, at most three colors
    /// and never none, strengths, fades and color components within 0 through
    /// 1, the gradient angle within a turn, and crest layers addressing a color
    /// that exists. The crest's own palette is dropped when it holds no color,
    /// its composition parameters stay within the ranges the renderer draws,
    /// and a custom figure that is the crest's own symbol is no custom figure.
    /// It announces the readability and rendering vocabulary its values need.
    public static SpaceBranding Normalize(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        branding = branding.InTodaysUnits();
        var colors = branding.Colors.Colors.Take(MaximumColorCount).Select(Color).ToArray();
        if (colors.Length == 0) colors = [DefaultColor];
        var palette = branding.Crest.Palette?.Colors.Take(MaximumCrestPaletteCount).Select(Color).ToArray();
        if (palette is { Length: 0 }) palette = null;
        int layers = LayerColorCount(palette?.Length, colors.Length);
        var crest = branding.Crest;
        return Announced(branding with {
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
                PlateScale = CrestMeasure.PlateScale.Clamped(crest.PlateScale),
                EdgeWidth = CrestMeasure.EdgeWidth.Clamped(crest.EdgeWidth),
                DivisionCount = CrestMeasure.DivisionCount.Clamped(crest.DivisionCount),
                OrdinaryWidth = CrestMeasure.OrdinaryWidth.Clamped(crest.OrdinaryWidth),
                TrimWeight = CrestMeasure.TrimWeight.Clamped(crest.TrimWeight),
                TrimDetail = CrestMeasure.TrimDetail.Clamped(crest.TrimDetail),
                ChargeScale = CrestMeasure.ChargeScale.Clamped(crest.ChargeScale),
                ChargeOffset = CrestMeasure.ChargeOffset.Clamped(crest.ChargeOffset),
                SheenAngle = CrestMeasure.SheenAngle.Clamped(crest.SheenAngle),
                SealTeeth = CrestMeasure.SealTeeth.Clamped(crest.SealTeeth)
            }
        });
    }

    /// `look` with the readability and rendering vocabulary it announces worked
    /// out from its values.
    public static SpaceBranding Announced(SpaceBranding look) {
        ArgumentNullException.ThrowIfNull(look);
        return look with { KeepsControlsReadable = look.ReadabilityFade > 0, RenderingVersion = RenderingVersion(look) };
    }

    /// A crest's custom figure as the renderer draws it: names and letters
    /// trimmed, one emoji, a monogram of at most two capitals, nothing drawn in
    /// place of an empty one, and none at all when it is the crest's own symbol.
    public static CrestCharge? Charge(CrestCharge? charge, CrestSymbol symbol) {
        if (charge is null) return null;
        string text = charge.Text?.Trim() ?? "";
        var figure = charge.Kind.Kind switch {
            CrestChargeKind.Kinds.System => text.Length == 0 ? new(CrestChargeKind.None) : charge with { Text = text },
            CrestChargeKind.Kinds.Emoji => string.IsNullOrEmpty(charge.Text) ? new(CrestChargeKind.None)
                : charge with { Text = new System.Globalization.StringInfo(charge.Text).SubstringByTextElements(0, 1) },
            CrestChargeKind.Kinds.Monogram => text.Length == 0 ? new(CrestChargeKind.None) : charge with {
                Text = FirstTextElements(text.ToUpperInvariant(), MaximumMonogramLength).ToUpperInvariant()
            },
            _ => charge
        };
        return figure.Kind == CrestChargeKind.Heraldic && figure.Symbol == symbol ? null : figure;
    }

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

    #region Actions - Rendering vocabulary

    /// The rendering vocabulary `branding` needs, which is the version it
    /// announces: the newest vocabulary any of its terms is drawn since, and
    /// the Studio's when it sets a Studio parameter or a color of its own.
    /// Every Apple client computes it this way when it writes a branding.
    public static int RenderingVersion(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        var crest = branding.Crest;
        CrestVocabulary[] needed = [
            branding.BannerPattern.DrawnSince, crest.Symbol.DrawnSince, crest.Backplate.DrawnSince, crest.FieldDivision.DrawnSince,
            crest.Ordinary.DrawnSince, crest.Trim.DrawnSince, crest.ChargeLayout.DrawnSince, crest.Finish.DrawnSince,
            crest.Depth.DrawnSince, crest.ChargeWeight.DrawnSince,
            branding.SymbolColor is null ? CrestVocabulary.Baseline : CrestVocabulary.Customization,
            UsesStudioParameters(crest) ? CrestVocabulary.Studio : CrestVocabulary.Baseline
        ];
        return needed.Max(vocabulary => vocabulary.Version);
    }

    /// Whether the crest moves a measure only the Studio vocabulary draws off
    /// its default, draws an outline, or wears colors or a figure of its own.
    private static bool UsesStudioParameters(SpaceCrest crest) =>
        crest.Palette is not null || crest.Charge is not null || crest.ShowsOutline
        || CrestMeasure.All.Any(measure => measure.IsMoved(crest));

    #endregion
}
