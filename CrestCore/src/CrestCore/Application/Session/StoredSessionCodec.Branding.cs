using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Static Variables

    /// Branding stored before rendering versions were recorded is version one.
    private const int FirstRenderingVersion = 1;

    #endregion

    #region Actions - Branding

    /// A Space's branding, with the native reader's defaults for anything missing
    /// and for a term this build cannot name. Colors that are not color records
    /// are left out, and a palette color's gradient that is not a gradient
    /// record is plain.
    internal static SpaceBranding DecodeBranding(JsonNode? node) {
        var value = Object(node);
        var fade = OptionalNumber(value[Key.ReadabilityFade]);
        var keepsReadable = Flag(value[Key.KeepsControlsReadable]);
        fade ??= keepsReadable ?? true ? SpaceBranding.LegacyReadabilityFade : 0;
        return new(Palette(value[Key.Colors]) ?? new([]),
            SpaceBannerPattern.Named(Text(value[Key.BannerPattern])) ?? SpaceBannerPattern.Solid,
            OptionalNumber(value[Key.BannerStrength]) ?? 1, fade.Value, keepsReadable ?? fade > 0,
            SpaceThemeMode.Named(Text(value[Key.ThemeMode])) ?? SpaceThemeMode.Banner,
            OptionalNumber(value[Key.GradientAngle]) ?? 0,
            Texture(Flag(value[Key.ShowsTexture]), OptionalNumber(value[Key.TextureStrength])),
            SpaceIconStyle.Named(Text(value[Key.IconStyle])) ?? SpaceIconStyle.SimpleSymbol,
            value[Key.SymbolColor] is JsonObject symbolColor ? DecodeColor(symbolColor) : null,
            DecodeCrest(value[Key.Crest] as JsonObject ?? []),
            Integer(value[Key.RenderingVersion]) ?? FirstRenderingVersion,
            OptionalNumber(value[Key.FolderColorIntensity]) ?? 0,
            SpaceTextColorMode.Named(Text(value[Key.TextColorMode])) ?? SpaceTextColorMode.Automatic,
            Flag(value[Key.HasCustomAppearance]),
            SpaceGradientKind.Named(Text(value[Key.GradientKind])),
            value[Key.SymbolGradient] is JsonObject symbolGradient ? DecodeGradient(symbolGradient) : null,
            value[Key.ColorGradients] is JsonArray colorGradients ? DecodeGradients(colorGradients) : null);
    }

    /// The texture strength a branding stored by any build lies under. A build
    /// that keeps only whether a texture shows writes the switch alone, and
    /// can turn it on over a strength of none: the switch decides, and a texture
    /// it shows with no strength of its own is full.
    internal static double Texture(bool? shows, double? strength) => shows switch {
        false => 0,
        true => strength is > 0 and var stored ? stored : 1,
        null => strength ?? 0
    };

    /// A branding as the stored session and sync keep it. Whether a texture
    /// shows is the switch builds before texture strength read, and the
    /// strength is written only where the switch alone can't say it, between
    /// none and full. A gradient's kind is written only when it isn't linear,
    /// and the gradients its colors run on into only when it has them, which
    /// builds before them pass over to draw each color plain.
    internal static JsonObject Encode(SpaceBranding branding) {
        var value = new JsonObject {
            [Key.Colors] = Encode(branding.Colors),
            [Key.BannerPattern] = branding.BannerPattern.Name,
            [Key.BannerStrength] = branding.BannerStrength,
            [Key.ReadabilityFade] = branding.ReadabilityFade,
            [Key.KeepsControlsReadable] = branding.KeepsControlsReadable,
            [Key.ThemeMode] = branding.ThemeMode.Name,
            [Key.GradientAngle] = branding.GradientAngle,
            [Key.ShowsTexture] = branding.TextureStrength > 0,
            [Key.IconStyle] = branding.IconStyle.Name
        };
        if (branding.TextureStrength is > 0 and < 1) value[Key.TextureStrength] = branding.TextureStrength;
        if (branding.SymbolColor is { } symbolColor) value[Key.SymbolColor] = Encode(symbolColor);
        value[Key.Crest] = Encode(branding.Crest);
        value[Key.RenderingVersion] = branding.RenderingVersion;
        value[Key.FolderColorIntensity] = branding.FolderColorIntensity;
        value[Key.TextColorMode] = branding.TextColorMode.Name;
        if (branding.HasCustomAppearance is { } custom) value[Key.HasCustomAppearance] = custom;
        if (branding.GradientKind is { } kind && kind != SpaceGradientKind.Linear) value[Key.GradientKind] = kind.Name;
        if (branding.SymbolGradient is { } symbolGradient) value[Key.SymbolGradient] = Encode(symbolGradient);
        if (branding.ColorGradients is { } colorGradients) value[Key.ColorGradients] = Encode(colorGradients);
        return value;
    }

    /// The gradient a color runs on into. Colors that are not color records are
    /// left out, a kind this build cannot name runs along a line, and the angle
    /// is none unless it says.
    internal static BrandGradient DecodeGradient(JsonObject value) =>
        new(Palette(value[Key.Colors]) ?? new([]), SpaceGradientKind.Named(TolerantText(value[Key.Kind])),
            OptionalNumber(value[Key.Angle]) ?? 0);

    /// A gradient as the stored session and sync keep it, its kind written
    /// only when it isn't linear.
    internal static JsonObject Encode(BrandGradient gradient) {
        var value = new JsonObject { [Key.Colors] = Encode(gradient.Colors) };
        if (gradient.Kind is { } kind && kind != SpaceGradientKind.Linear) value[Key.Kind] = kind.Name;
        value[Key.Angle] = gradient.Angle;
        return value;
    }

    /// The gradients a palette's colors run on into, by index; a slot that is
    /// not a gradient record is plain.
    private static PaletteGradients DecodeGradients(JsonArray slots) =>
        new([.. slots.Select(slot => slot is JsonObject gradient ? DecodeGradient(gradient) : BrandGradient.Plain)]);

    private static JsonArray Encode(PaletteGradients gradients) =>
        new(gradients.Slots.Select(slot => (JsonNode?)Encode(slot)).ToArray());

    /// A crest composition. Missing layer indices read as the first color, the
    /// edge follows the trim, a palette color's gradient that is not a gradient
    /// record is plain, and every other parameter takes its neutral value.
    internal static SpaceCrest DecodeCrest(JsonObject value) {
        int Index(string key, int fallback = 0) => Integer(value[key]) ?? fallback;
        double Measure(CrestMeasure measure) => OptionalNumber(value[measure.Name]) ?? measure.Default;
        int Count(CrestMeasure measure) => Integer(value[measure.Name]) ?? (int)measure.Default;
        return new(CrestBackplate.Named(Text(value[Key.Backplate])) ?? CrestBackplate.Shield,
            CrestFieldDivision.Named(Text(value[Key.FieldDivision])) ?? CrestFieldDivision.Plain,
            CrestOrdinary.Named(Text(value[Key.Ordinary])) ?? CrestOrdinary.None,
            CrestTrim.Named(Text(value[Key.Trim])) ?? CrestTrim.None,
            CrestSymbol.Named(Text(value[Key.Symbol])) ?? CrestSymbol.Fallback,
            CrestChargeLayout.Named(Text(value[Key.ChargeLayout])) ?? CrestChargeLayout.Single,
            Index(Key.BackplateColorIndex), Index(Key.SecondaryFieldColorIndex), Index(Key.OrdinaryColorIndex),
            Index(Key.TrimColorIndex), Index(Key.SymbolColorIndex), TolerantText(value[Key.StartingPresetId]),
            Index(Key.EdgeColorIndex, Index(Key.TrimColorIndex)), Palette(value[Key.Palette]),
            value[Key.Charge] is JsonObject charge ? DecodeCharge(charge) : null,
            Measure(CrestMeasure.PlateScale), Measure(CrestMeasure.EdgeWidth), Count(CrestMeasure.DivisionCount),
            CrestFinish.Named(Text(value[Key.Finish])) ?? CrestFinish.Flat,
            Measure(CrestMeasure.OrdinaryWidth), Measure(CrestMeasure.TrimWeight), Count(CrestMeasure.TrimDetail),
            Measure(CrestMeasure.ChargeScale), Measure(CrestMeasure.ChargeOffset),
            CrestChargeWeight.Named(Text(value[Key.ChargeWeight])) ?? CrestChargeWeight.Bold,
            Measure(CrestMeasure.SheenAngle), Count(CrestMeasure.SealTeeth), TolerantFlag(value[Key.ShowsOutline]) ?? false,
            CrestDepth.Named(Text(value[Key.Depth])) ?? CrestDepth.None,
            value[Key.PaletteGradients] is JsonArray paletteGradients ? DecodeGradients(paletteGradients) : null);
    }

    /// A crest as the stored session and sync keep it, with the gradients its
    /// own palette's colors run on into only when it has them, which builds
    /// before them pass over to draw each color plain.
    internal static JsonObject Encode(SpaceCrest crest) {
        var value = new JsonObject {
            [Key.Backplate] = crest.Backplate.Name,
            [Key.FieldDivision] = crest.FieldDivision.Name,
            [Key.Ordinary] = crest.Ordinary.Name,
            [Key.Trim] = crest.Trim.Name,
            [Key.Symbol] = crest.Symbol.Name,
            [Key.ChargeLayout] = crest.ChargeLayout.Name,
            [Key.BackplateColorIndex] = crest.BackplateColorIndex,
            [Key.SecondaryFieldColorIndex] = crest.SecondaryFieldColorIndex,
            [Key.OrdinaryColorIndex] = crest.OrdinaryColorIndex,
            [Key.TrimColorIndex] = crest.TrimColorIndex,
            [Key.SymbolColorIndex] = crest.SymbolColorIndex
        };
        Put(value, Key.StartingPresetId, crest.StartingPresetId);
        value[Key.EdgeColorIndex] = crest.EdgeColorIndex;
        if (crest.Palette is { } palette) value[Key.Palette] = Encode(palette);
        if (crest.PaletteGradients is { } paletteGradients) value[Key.PaletteGradients] = Encode(paletteGradients);
        if (crest.Charge is { } charge) value[Key.Charge] = Encode(charge);
        value[CrestMeasure.PlateScale.Name] = crest.PlateScale;
        value[CrestMeasure.EdgeWidth.Name] = crest.EdgeWidth;
        value[CrestMeasure.DivisionCount.Name] = crest.DivisionCount;
        value[Key.Finish] = crest.Finish.Name;
        value[CrestMeasure.OrdinaryWidth.Name] = crest.OrdinaryWidth;
        value[CrestMeasure.TrimWeight.Name] = crest.TrimWeight;
        value[CrestMeasure.TrimDetail.Name] = crest.TrimDetail;
        value[CrestMeasure.ChargeScale.Name] = crest.ChargeScale;
        value[CrestMeasure.ChargeOffset.Name] = crest.ChargeOffset;
        value[Key.ChargeWeight] = crest.ChargeWeight.Name;
        value[CrestMeasure.SheenAngle.Name] = crest.SheenAngle;
        value[CrestMeasure.SealTeeth.Name] = crest.SealTeeth;
        value[Key.ShowsOutline] = crest.ShowsOutline;
        value[Key.Depth] = crest.Depth.Name;
        return value;
    }

    /// A custom figure. An unknown kind draws nothing, a heraldic figure this
    /// build cannot name is the mountain, and a monogram is serif unless it says.
    internal static CrestCharge DecodeCharge(JsonObject value) {
        var text = TolerantText(value[Key.Value]) ?? "";
        var kind = CrestChargeKind.Named(TolerantText(value[Key.Kind])) ?? CrestChargeKind.None;
        return kind.Read(text, TolerantText(value[Key.Style]));
    }

    internal static JsonObject Encode(CrestCharge charge) {
        var value = new JsonObject { [Key.Kind] = charge.Kind.Name };
        var (stored, style) = charge.Kind.Written(charge);
        if (stored is not null) value[Key.Value] = stored;
        if (style is not null) value[Key.Style] = style;
        return value;
    }

    private static ColorPalette? Palette(JsonNode? node) =>
        node is JsonArray colors ? new([.. colors.OfType<JsonObject>().Select(DecodeColor)]) : null;

    private static JsonArray Encode(ColorPalette palette) => new(palette.Colors.Select(color => (JsonNode?)Encode(color)).ToArray());

    #endregion
}
