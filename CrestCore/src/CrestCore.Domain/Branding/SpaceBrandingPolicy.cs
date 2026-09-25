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

    /// The rendering vocabulary every shipped build draws.
    public const int BaselineRenderingVersion = 2;
    /// The vocabulary that adds the expanded heraldic charges.
    public const int ExpandedChargeRenderingVersion = 3;
    /// The vocabulary that adds the customization surfaces and backplates.
    public const int CustomizationRenderingVersion = 4;
    /// The Crest Studio vocabulary: parametric shapes, own tinctures, custom
    /// charges, finishes and depth.
    public const int StudioRenderingVersion = 5;
    /// How many pieces a counted field division draws unless set.
    public const int DefaultDivisionCount = 4;
    /// How much detail a counted trim draws unless set.
    public const int DefaultTrimDetail = 12;

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

    #region Actions - Rendering vocabulary

    /// The rendering vocabulary `branding` needs, which is the version it
    /// announces: the shipped baseline unless it wears a term, a symbol color
    /// or a Studio parameter that a later vocabulary added. Every Apple client
    /// computes it this way when it writes a branding.
    public static int RenderingVersion(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        var crest = branding.Crest;
        return new[] {
            branding.SymbolColor is null ? BaselineRenderingVersion : CustomizationRenderingVersion,
            branding.BannerPattern is SpaceBannerPattern.Stripes or SpaceBannerPattern.Checkered or SpaceBannerPattern.Lozenges
                ? CustomizationRenderingVersion : BaselineRenderingVersion,
            Introduced(crest.Symbol),
            crest.Backplate switch {
                CrestBackplate.Octagon or CrestBackplate.RoundedSquare => CustomizationRenderingVersion,
                CrestBackplate.FrenchShield or CrestBackplate.Oval or CrestBackplate.Banner or CrestBackplate.Badge => StudioRenderingVersion,
                _ => BaselineRenderingVersion
            },
            crest.FieldDivision is CrestFieldDivision.PerSaltire || IsCounted(crest.FieldDivision) ? StudioRenderingVersion : BaselineRenderingVersion,
            crest.Ordinary is CrestOrdinary.Pall or CrestOrdinary.Pile or CrestOrdinary.Canton or CrestOrdinary.Roundel
                ? StudioRenderingVersion : BaselineRenderingVersion,
            crest.Trim is CrestTrim.Line or CrestTrim.DoubleLine or CrestTrim.Beaded ? StudioRenderingVersion : BaselineRenderingVersion,
            crest.ChargeLayout is CrestChargeLayout.Quad or CrestChargeLayout.Ring ? StudioRenderingVersion : BaselineRenderingVersion,
            UsesStudioParameters(crest) ? StudioRenderingVersion : BaselineRenderingVersion
        }.Max();
    }

    /// The vocabulary that first drew `symbol`.
    private static int Introduced(CrestSymbol symbol) => symbol switch {
        CrestSymbol.Dragon or CrestSymbol.Direwolf or CrestSymbol.Lion or CrestSymbol.Stag or CrestSymbol.Raven or CrestSymbol.Griffin
            or CrestSymbol.Eagle or CrestSymbol.Bear or CrestSymbol.Boar or CrestSymbol.Fox or CrestSymbol.Horse or CrestSymbol.Unicorn
            or CrestSymbol.Wyvern or CrestSymbol.Hydra or CrestSymbol.Serpent or CrestSymbol.Kraken or CrestSymbol.Seahorse
            or CrestSymbol.Scorpion or CrestSymbol.Bat or CrestSymbol.Falcon or CrestSymbol.Rose or CrestSymbol.Lily or CrestSymbol.Pine
            or CrestSymbol.Willow or CrestSymbol.Swords or CrestSymbol.Axes or CrestSymbol.Sword or CrestSymbol.Trident
            or CrestSymbol.Anchor or CrestSymbol.Castle or CrestSymbol.Scales or CrestSymbol.DragonHead => StudioRenderingVersion,
        CrestSymbol.Paw or CrestSymbol.Hound or CrestSymbol.Crown or CrestSymbol.RisingSun or CrestSymbol.CrossedBanners
            or CrestSymbol.Flower or CrestSymbol.Drop or CrestSymbol.Snowflake or CrestSymbol.Horn => ExpandedChargeRenderingVersion,
        _ => BaselineRenderingVersion
    };

    /// Whether a field division draws a counted number of pieces.
    private static bool IsCounted(CrestFieldDivision division) =>
        division is CrestFieldDivision.Gyronny or CrestFieldDivision.Barry or CrestFieldDivision.Paly or CrestFieldDivision.Checky;

    /// Whether the crest uses a control only the Studio vocabulary draws.
    private static bool UsesStudioParameters(SpaceCrest crest) =>
        crest.Palette is not null || crest.Charge is not null || crest.PlateScale != 1 || crest.EdgeWidth != 0
        || (IsCounted(crest.FieldDivision) && crest.DivisionCount != DefaultDivisionCount) || crest.Finish != CrestFinish.Flat
        || crest.SheenAngle != 45 || crest.ShowsOutline || (crest.Backplate == CrestBackplate.Seal && crest.SealTeeth != 12)
        || crest.OrdinaryWidth != 1 || crest.TrimWeight != 1
        || (crest.Trim is CrestTrim.Sunburst or CrestTrim.Beaded && crest.TrimDetail != DefaultTrimDetail)
        || crest.ChargeScale != 1 || crest.ChargeOffset != 0 || crest.ChargeWeight != CrestChargeWeight.Bold || crest.Depth != CrestDepth.None;

    #endregion
}
