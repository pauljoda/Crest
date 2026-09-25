using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    internal static readonly StoredSpellings<SpaceBannerPattern> SpaceBannerPatterns = new([
        (SpaceBannerPattern.Solid, "solid"), (SpaceBannerPattern.Split, "split"), (SpaceBannerPattern.Bands, "bands"),
        (SpaceBannerPattern.Diagonal, "diagonal"), (SpaceBannerPattern.Chevron, "chevron"),
        (SpaceBannerPattern.Quartered, "quartered"), (SpaceBannerPattern.Stripes, "stripes"),
        (SpaceBannerPattern.Checkered, "checkered"), (SpaceBannerPattern.Lozenges, "lozenges")
    ]);
    internal static readonly StoredSpellings<SpaceThemeMode> SpaceThemeModes = new([
        (SpaceThemeMode.Banner, "banner"), (SpaceThemeMode.Gradient, "gradient")
    ]);
    internal static readonly StoredSpellings<SpaceIconStyle> SpaceIconStyles = new([
        (SpaceIconStyle.SimpleSymbol, "simpleSymbol"), (SpaceIconStyle.LayeredCrest, "layeredCrest")
    ]);
    internal static readonly StoredSpellings<SpaceTextColorMode> SpaceTextColorModes = new([
        (SpaceTextColorMode.Automatic, "automatic"), (SpaceTextColorMode.Light, "light"),
        (SpaceTextColorMode.Dark, "dark")
    ]);
    internal static readonly StoredSpellings<CrestBackplate> CrestBackplates = new([
        (CrestBackplate.None, "none"), (CrestBackplate.Circle, "circle"), (CrestBackplate.Shield, "shield"),
        (CrestBackplate.FrenchShield, "frenchShield"), (CrestBackplate.Diamond, "diamond"),
        (CrestBackplate.Seal, "seal"), (CrestBackplate.Hexagon, "hexagon"), (CrestBackplate.Octagon, "octagon"),
        (CrestBackplate.RoundedSquare, "roundedSquare"), (CrestBackplate.Oval, "oval"),
        (CrestBackplate.Banner, "banner"), (CrestBackplate.Badge, "badge")
    ]);
    internal static readonly StoredSpellings<CrestFieldDivision> CrestFieldDivisions = new([
        (CrestFieldDivision.Plain, "plain"), (CrestFieldDivision.PerPale, "perPale"),
        (CrestFieldDivision.PerFess, "perFess"), (CrestFieldDivision.PerBend, "perBend"),
        (CrestFieldDivision.PerChevron, "perChevron"), (CrestFieldDivision.Quarterly, "quarterly"),
        (CrestFieldDivision.PerSaltire, "perSaltire"), (CrestFieldDivision.Gyronny, "gyronny"),
        (CrestFieldDivision.Barry, "barry"), (CrestFieldDivision.Paly, "paly"), (CrestFieldDivision.Checky, "checky")
    ]);
    internal static readonly StoredSpellings<CrestOrdinary> CrestOrdinaries = new([
        (CrestOrdinary.None, "none"), (CrestOrdinary.Pale, "pale"), (CrestOrdinary.Fess, "fess"),
        (CrestOrdinary.Bend, "bend"), (CrestOrdinary.Chevron, "chevron"), (CrestOrdinary.Cross, "cross"),
        (CrestOrdinary.Saltire, "saltire"), (CrestOrdinary.Chief, "chief"), (CrestOrdinary.Bordure, "bordure"),
        (CrestOrdinary.Pall, "pall"), (CrestOrdinary.Pile, "pile"), (CrestOrdinary.Canton, "canton"),
        (CrestOrdinary.Roundel, "roundel")
    ]);
    internal static readonly StoredSpellings<CrestTrim> CrestTrims = new([
        (CrestTrim.None, "none"), (CrestTrim.Shield, "shield"), (CrestTrim.Line, "line"),
        (CrestTrim.DoubleLine, "doubleLine"), (CrestTrim.Laurel, "laurel"), (CrestTrim.Sunburst, "sunburst"),
        (CrestTrim.DoubleRing, "doubleRing"), (CrestTrim.Seal, "seal"), (CrestTrim.Beaded, "beaded")
    ]);
    internal static readonly StoredSpellings<CrestSymbol> CrestSymbols = new([
        (CrestSymbol.Dragon, "dragon"), (CrestSymbol.Direwolf, "direwolf"), (CrestSymbol.Lion, "lion"),
        (CrestSymbol.Stag, "stag"), (CrestSymbol.Raven, "raven"), (CrestSymbol.Griffin, "griffin"),
        (CrestSymbol.Eagle, "eagle"), (CrestSymbol.Bear, "bear"), (CrestSymbol.Boar, "boar"),
        (CrestSymbol.Fox, "fox"), (CrestSymbol.Horse, "horse"), (CrestSymbol.Unicorn, "unicorn"),
        (CrestSymbol.Wyvern, "wyvern"), (CrestSymbol.Hydra, "hydra"), (CrestSymbol.Serpent, "serpent"),
        (CrestSymbol.Kraken, "kraken"), (CrestSymbol.Seahorse, "seahorse"), (CrestSymbol.Scorpion, "scorpion"),
        (CrestSymbol.Bat, "bat"), (CrestSymbol.Falcon, "falcon"), (CrestSymbol.Rose, "rose"),
        (CrestSymbol.Lily, "lily"), (CrestSymbol.Pine, "pine"), (CrestSymbol.Willow, "willow"),
        (CrestSymbol.Swords, "swords"), (CrestSymbol.Axes, "axes"), (CrestSymbol.Sword, "sword"),
        (CrestSymbol.Trident, "trident"), (CrestSymbol.Anchor, "anchor"), (CrestSymbol.Castle, "castle"),
        (CrestSymbol.Scales, "scales"), (CrestSymbol.DragonHead, "dragonHead"), (CrestSymbol.Hound, "hound"),
        (CrestSymbol.Paw, "paw"), (CrestSymbol.Hare, "hare"), (CrestSymbol.Bird, "bird"), (CrestSymbol.Fish, "fish"),
        (CrestSymbol.Bee, "bee"), (CrestSymbol.Shell, "shell"), (CrestSymbol.Sun, "sun"),
        (CrestSymbol.RisingSun, "risingSun"), (CrestSymbol.Crescent, "crescent"), (CrestSymbol.Star, "star"),
        (CrestSymbol.Sparkles, "sparkles"), (CrestSymbol.Lightning, "lightning"), (CrestSymbol.Flame, "flame"),
        (CrestSymbol.Snowflake, "snowflake"), (CrestSymbol.Drop, "drop"), (CrestSymbol.Mountain, "mountain"),
        (CrestSymbol.Tree, "tree"), (CrestSymbol.Oak, "oak"), (CrestSymbol.Leaf, "leaf"), (CrestSymbol.Fern, "fern"),
        (CrestSymbol.Flower, "flower"), (CrestSymbol.Waves, "waves"), (CrestSymbol.Tower, "tower"),
        (CrestSymbol.Book, "book"), (CrestSymbol.Key, "key"), (CrestSymbol.Hammer, "hammer"),
        (CrestSymbol.Compass, "compass"), (CrestSymbol.Sailboat, "sailboat"), (CrestSymbol.Crown, "crown"),
        (CrestSymbol.Horn, "horn"), (CrestSymbol.CrossedBanners, "crossedBanners")
    ]);
    internal static readonly StoredSpellings<CrestChargeLayout> CrestChargeLayouts = new([
        (CrestChargeLayout.Single, "single"), (CrestChargeLayout.Paired, "paired"), (CrestChargeLayout.Trio, "trio"),
        (CrestChargeLayout.Quad, "quad"), (CrestChargeLayout.Ring, "ring")
    ]);
    internal static readonly StoredSpellings<CrestFinish> CrestFinishes = new([
        (CrestFinish.Flat, "flat"), (CrestFinish.Sheen, "sheen"), (CrestFinish.Embossed, "embossed")
    ]);
    internal static readonly StoredSpellings<CrestDepth> CrestDepths = new([
        (CrestDepth.None, "none"), (CrestDepth.Soft, "soft"), (CrestDepth.Lifted, "lifted")
    ]);
    internal static readonly StoredSpellings<CrestChargeWeight> CrestChargeWeights = new([
        (CrestChargeWeight.Light, "light"), (CrestChargeWeight.Regular, "regular"), (CrestChargeWeight.Bold, "bold")
    ]);
    internal static readonly StoredSpellings<CrestMonogramStyle> CrestMonogramStyles = new([
        (CrestMonogramStyle.Serif, "serif"), (CrestMonogramStyle.Sans, "sans")
    ]);
    internal static readonly StoredSpellings<CrestChargeKind> CrestChargeKinds = new([
        (CrestChargeKind.Heraldic, "heraldic"), (CrestChargeKind.System, "system"), (CrestChargeKind.Emoji, "emoji"),
        (CrestChargeKind.Monogram, "monogram"), (CrestChargeKind.None, "none")
    ]);

    /// Branding stored before rendering versions were recorded is version one.
    private const int FirstRenderingVersion = 1;

    #endregion

    #region Actions - Branding

    /// A Space's branding, with the native reader's defaults for anything missing
    /// and for a term this build cannot name. Colors that are not color records
    /// are left out.
    internal static SpaceBranding DecodeBranding(JsonNode? node) {
        var value = Object(node);
        var fade = OptionalNumber(value[Key.ReadabilityFade]);
        var keepsReadable = Flag(value[Key.KeepsControlsReadable]);
        fade ??= keepsReadable ?? true ? SpaceBranding.LegacyReadabilityFade : 0;
        return new(Palette(value[Key.Colors]) ?? new([]),
            SpaceBannerPatterns.Parse(Text(value[Key.BannerPattern])) ?? SpaceBannerPattern.Solid,
            OptionalNumber(value[Key.BannerStrength]) ?? 1, fade.Value, keepsReadable ?? fade > 0,
            SpaceThemeModes.Parse(Text(value[Key.ThemeMode])) ?? SpaceThemeMode.Banner,
            OptionalNumber(value[Key.GradientAngle]) ?? 0, Flag(value[Key.ShowsTexture]) ?? false,
            SpaceIconStyles.Parse(Text(value[Key.IconStyle])) ?? SpaceIconStyle.SimpleSymbol,
            value[Key.SymbolColor] is JsonObject symbolColor ? DecodeColor(symbolColor) : null,
            DecodeCrest(value[Key.Crest] as JsonObject ?? []),
            Integer(value[Key.RenderingVersion]) ?? FirstRenderingVersion,
            OptionalNumber(value[Key.FolderColorIntensity]) ?? 0,
            SpaceTextColorModes.Parse(Text(value[Key.TextColorMode])) ?? SpaceTextColorMode.Automatic,
            Flag(value[Key.HasCustomAppearance]));
    }

    internal static JsonObject Encode(SpaceBranding branding) {
        var value = new JsonObject {
            [Key.Colors] = Encode(branding.Colors),
            [Key.BannerPattern] = SpaceBannerPatterns.Name(branding.BannerPattern),
            [Key.BannerStrength] = branding.BannerStrength,
            [Key.ReadabilityFade] = branding.ReadabilityFade,
            [Key.KeepsControlsReadable] = branding.KeepsControlsReadable,
            [Key.ThemeMode] = SpaceThemeModes.Name(branding.ThemeMode),
            [Key.GradientAngle] = branding.GradientAngle,
            [Key.ShowsTexture] = branding.ShowsTexture,
            [Key.IconStyle] = SpaceIconStyles.Name(branding.IconStyle)
        };
        if (branding.SymbolColor is { } symbolColor) value[Key.SymbolColor] = Encode(symbolColor);
        value[Key.Crest] = Encode(branding.Crest);
        value[Key.RenderingVersion] = branding.RenderingVersion;
        value[Key.FolderColorIntensity] = branding.FolderColorIntensity;
        value[Key.TextColorMode] = SpaceTextColorModes.Name(branding.TextColorMode);
        if (branding.HasCustomAppearance is { } custom) value[Key.HasCustomAppearance] = custom;
        return value;
    }

    /// A crest composition. Missing layer indices read as the first color, the
    /// edge follows the trim, and every other parameter takes its neutral value.
    internal static SpaceCrest DecodeCrest(JsonObject value) {
        int Index(string key, int fallback = 0) => Integer(value[key]) ?? fallback;
        double Measure(string key, double fallback) => OptionalNumber(value[key]) ?? fallback;
        return new(CrestBackplates.Parse(Text(value[Key.Backplate])) ?? CrestBackplate.Shield,
            CrestFieldDivisions.Parse(Text(value[Key.FieldDivision])) ?? CrestFieldDivision.Plain,
            CrestOrdinaries.Parse(Text(value[Key.Ordinary])) ?? CrestOrdinary.None,
            CrestTrims.Parse(Text(value[Key.Trim])) ?? CrestTrim.None,
            CrestSymbols.Parse(Text(value[Key.Symbol])) ?? CrestSymbol.Mountain,
            CrestChargeLayouts.Parse(Text(value[Key.ChargeLayout])) ?? CrestChargeLayout.Single,
            Index(Key.BackplateColorIndex), Index(Key.SecondaryFieldColorIndex), Index(Key.OrdinaryColorIndex),
            Index(Key.TrimColorIndex), Index(Key.SymbolColorIndex), TolerantText(value[Key.StartingPresetId]),
            Index(Key.EdgeColorIndex, Index(Key.TrimColorIndex)), Palette(value[Key.Palette]),
            value[Key.Charge] is JsonObject charge ? DecodeCharge(charge) : null,
            Measure(Key.PlateScale, 1), Measure(Key.EdgeWidth, 0), Index(Key.DivisionCount, 4),
            CrestFinishes.Parse(Text(value[Key.Finish])) ?? CrestFinish.Flat,
            Measure(Key.OrdinaryWidth, 1), Measure(Key.TrimWeight, 1), Index(Key.TrimDetail, 12),
            Measure(Key.ChargeScale, 1), Measure(Key.ChargeOffset, 0),
            CrestChargeWeights.Parse(Text(value[Key.ChargeWeight])) ?? CrestChargeWeight.Bold,
            Measure(Key.SheenAngle, 45), Index(Key.SealTeeth, 12), TolerantFlag(value[Key.ShowsOutline]) ?? false,
            CrestDepths.Parse(Text(value[Key.Depth])) ?? CrestDepth.None);
    }

    internal static JsonObject Encode(SpaceCrest crest) {
        var value = new JsonObject {
            [Key.Backplate] = CrestBackplates.Name(crest.Backplate),
            [Key.FieldDivision] = CrestFieldDivisions.Name(crest.FieldDivision),
            [Key.Ordinary] = CrestOrdinaries.Name(crest.Ordinary),
            [Key.Trim] = CrestTrims.Name(crest.Trim),
            [Key.Symbol] = CrestSymbols.Name(crest.Symbol),
            [Key.ChargeLayout] = CrestChargeLayouts.Name(crest.ChargeLayout),
            [Key.BackplateColorIndex] = crest.BackplateColorIndex,
            [Key.SecondaryFieldColorIndex] = crest.SecondaryFieldColorIndex,
            [Key.OrdinaryColorIndex] = crest.OrdinaryColorIndex,
            [Key.TrimColorIndex] = crest.TrimColorIndex,
            [Key.SymbolColorIndex] = crest.SymbolColorIndex
        };
        Put(value, Key.StartingPresetId, crest.StartingPresetId);
        value[Key.EdgeColorIndex] = crest.EdgeColorIndex;
        if (crest.Palette is { } palette) value[Key.Palette] = Encode(palette);
        if (crest.Charge is { } charge) value[Key.Charge] = Encode(charge);
        value[Key.PlateScale] = crest.PlateScale;
        value[Key.EdgeWidth] = crest.EdgeWidth;
        value[Key.DivisionCount] = crest.DivisionCount;
        value[Key.Finish] = CrestFinishes.Name(crest.Finish);
        value[Key.OrdinaryWidth] = crest.OrdinaryWidth;
        value[Key.TrimWeight] = crest.TrimWeight;
        value[Key.TrimDetail] = crest.TrimDetail;
        value[Key.ChargeScale] = crest.ChargeScale;
        value[Key.ChargeOffset] = crest.ChargeOffset;
        value[Key.ChargeWeight] = CrestChargeWeights.Name(crest.ChargeWeight);
        value[Key.SheenAngle] = crest.SheenAngle;
        value[Key.SealTeeth] = crest.SealTeeth;
        value[Key.ShowsOutline] = crest.ShowsOutline;
        value[Key.Depth] = CrestDepths.Name(crest.Depth);
        return value;
    }

    /// A custom figure. An unknown kind draws nothing, a heraldic figure this
    /// build cannot name is the mountain, and a monogram is serif unless it says.
    internal static CrestCharge DecodeCharge(JsonObject value) {
        var text = TolerantText(value[Key.Value]) ?? "";
        return (CrestChargeKinds.Parse(TolerantText(value[Key.Kind])) ?? CrestChargeKind.None) switch {
            CrestChargeKind.Heraldic => new(CrestChargeKind.Heraldic, CrestSymbols.Parse(text) ?? CrestSymbol.Mountain),
            CrestChargeKind.System => new(CrestChargeKind.System, Text: text),
            CrestChargeKind.Emoji => new(CrestChargeKind.Emoji, Text: text),
            CrestChargeKind.Monogram => new(CrestChargeKind.Monogram, Text: text,
                Style: CrestMonogramStyles.Parse(TolerantText(value[Key.Style])) ?? CrestMonogramStyle.Serif),
            _ => new(CrestChargeKind.None)
        };
    }

    internal static JsonObject Encode(CrestCharge charge) {
        var value = new JsonObject { [Key.Kind] = CrestChargeKinds.Name(charge.Kind) };
        if (charge.Kind == CrestChargeKind.Heraldic && charge.Symbol is { } symbol) value[Key.Value] = CrestSymbols.Name(symbol);
        else if (charge.Kind != CrestChargeKind.None) value[Key.Value] = charge.Text ?? "";
        if (charge.Kind == CrestChargeKind.Monogram) value[Key.Style] = CrestMonogramStyles.Name(charge.Style ?? CrestMonogramStyle.Serif);
        return value;
    }

    private static ColorPalette? Palette(JsonNode? node) =>
        node is JsonArray colors ? new([.. colors.OfType<JsonObject>().Select(DecodeColor)]) : null;

    private static JsonArray Encode(ColorPalette palette) => new(palette.Colors.Select(color => (JsonNode?)Encode(color)).ToArray());

    #endregion
}
