using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed partial record SpacePayload {
    #region Static Variables

    /// The palette colors builds before stored colors named, which a record may
    /// still spell by name.
    private static readonly IReadOnlyDictionary<string, BrandColor> NamedColors = new Dictionary<string, BrandColor>(StringComparer.Ordinal) {
        ["ink"] = new(0.08, 0.15, 0.23),
        ["indigo"] = new(0.29, 0.25, 0.58),
        ["ocean"] = new(0.22, 0.42, 0.64),
        ["sky"] = new(0.35, 0.66, 0.84),
        ["teal"] = new(0.12, 0.49, 0.52),
        ["sage"] = new(0.39, 0.56, 0.42),
        ["gold"] = new(0.88, 0.67, 0.25),
        ["ember"] = new(0.85, 0.27, 0.20),
        ["rose"] = new(0.72, 0.25, 0.42),
        ["sand"] = new(0.82, 0.72, 0.56)
    };

    /// Branding stored before rendering versions were recorded is version one.
    private const int FirstRenderingVersion = 1;

    #endregion

    #region Actions - Branding

    /// A branding as every client reads it: its colors, strength and crest
    /// are required, a term a client cannot name takes its default, and every
    /// value is kept within the range the renderer draws. A branding from
    /// before rendering versions keeps its old banner strength's look.
    private static SpaceBranding ReadBranding(SyncPayloadReader value) {
        bool keepsReadable = value.OptionalFlag("keepsControlsReadable") ?? true;
        double fade = value.OptionalNumber("readabilityFade") ?? (keepsReadable ? SpaceBranding.LegacyReadabilityFade : 0);
        double strength = value.Number("bannerStrength");
        long version = value.OptionalInteger("renderingVersion") ?? FirstRenderingVersion;
        if (version < SpaceBranding.BaselineRenderingVersion) strength = Math.Min(1, 0.72 + strength * 0.28);
        var colors = value.Array("colors").Select(Color).ToArray();
        var branding = new SpaceBranding(new(colors),
            StoredSessionCodec.SpaceBannerPatterns.Parse(value.TolerantText("bannerPattern")) ?? SpaceBannerPattern.Solid,
            strength, fade, fade > 0,
            StoredSessionCodec.SpaceThemeModes.Parse(value.TolerantText("themeMode")) ?? SpaceThemeMode.Banner,
            value.OptionalNumber("gradientAngle") ?? 0, value.OptionalFlag("showsTexture") ?? false,
            StoredSessionCodec.SpaceIconStyles.Parse(value.TolerantText("iconStyle")) ?? SpaceIconStyle.SimpleSymbol,
            value.Value["symbolColor"] is { } symbolColor ? Color(symbolColor) : null,
            ReadCrest(value.Nested("crest")), FirstRenderingVersion, value.TolerantNumber("folderColorIntensity") ?? 0,
            StoredSessionCodec.SpaceTextColorModes.Parse(value.TolerantText("textColorMode")) ?? SpaceTextColorMode.Automatic,
            value.OptionalFlag("hasCustomAppearance"));
        return Resolved(branding);
    }

    /// A crest as every client reads it: each member it cannot read takes its
    /// neutral value, and a figure it cannot read is none.
    private static SpaceCrest ReadCrest(SyncPayloadReader value) {
        int Index(string key, int fallback = 0) => Whole(value.TolerantInteger(key) ?? fallback);
        double Measure(string key, double fallback) => value.TolerantNumber(key) ?? fallback;
        return new(StoredSessionCodec.CrestBackplates.Parse(value.TolerantText("backplate")) ?? CrestBackplate.Shield,
            StoredSessionCodec.CrestFieldDivisions.Parse(value.TolerantText("fieldDivision")) ?? CrestFieldDivision.Plain,
            StoredSessionCodec.CrestOrdinaries.Parse(value.TolerantText("ordinary")) ?? CrestOrdinary.None,
            StoredSessionCodec.CrestTrims.Parse(value.TolerantText("trim")) ?? CrestTrim.None,
            StoredSessionCodec.CrestSymbols.Parse(value.TolerantText("symbol")) ?? CrestSymbol.Mountain,
            StoredSessionCodec.CrestChargeLayouts.Parse(value.TolerantText("chargeLayout")) ?? CrestChargeLayout.Single,
            Index("backplateColorIndex"), Index("secondaryFieldColorIndex"), Index("ordinaryColorIndex"), Index("trimColorIndex"),
            Index("symbolColorIndex"), value.TolerantText("startingPresetID"), Index("edgeColorIndex", Index("trimColorIndex")),
            Palette(value.Value["palette"]), Charge(value.Value["charge"]),
            Measure("plateScale", 1), Measure("edgeWidth", 0), Index("divisionCount", SpaceBrandingPolicy.DefaultDivisionCount),
            StoredSessionCodec.CrestFinishes.Parse(value.TolerantText("finish")) ?? CrestFinish.Flat,
            Measure("ordinaryWidth", 1), Measure("trimWeight", 1), Index("trimDetail", SpaceBrandingPolicy.DefaultTrimDetail),
            Measure("chargeScale", 1), Measure("chargeOffset", 0),
            StoredSessionCodec.CrestChargeWeights.Parse(value.TolerantText("chargeWeight")) ?? CrestChargeWeight.Bold,
            Measure("sheenAngle", 45), Index("sealTeeth", 12), value.TolerantFlag("showsOutline") ?? false,
            StoredSessionCodec.CrestDepths.Parse(value.TolerantText("depth")) ?? CrestDepth.None);
    }

    /// A crest's own palette, or null when it has none every client reads.
    private static ColorPalette? Palette(JsonNode? node) {
        if (node is null) return null;
        try {
            return new([.. (node as JsonArray ?? throw new UnreadableSyncPayloadException()).Select(Color)]);
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// A crest's custom figure, or null when it has none every client reads. A
    /// kind no client knows draws nothing; a heraldic figure no client knows is
    /// the mountain; a monogram is serif unless it says.
    private static CrestCharge? Charge(JsonNode? node) {
        if (node is not JsonObject) return null;
        try {
            var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
            string text = value.OptionalText("value") ?? "";
            return (StoredSessionCodec.CrestChargeKinds.Parse(value.TolerantText("kind")) ?? CrestChargeKind.None) switch {
                CrestChargeKind.Heraldic => new(CrestChargeKind.Heraldic, StoredSessionCodec.CrestSymbols.Parse(text) ?? CrestSymbol.Mountain),
                CrestChargeKind.System => new(CrestChargeKind.System, Text: text),
                CrestChargeKind.Emoji => new(CrestChargeKind.Emoji, Text: text),
                CrestChargeKind.Monogram => new(CrestChargeKind.Monogram, Text: text,
                    Style: StoredSessionCodec.CrestMonogramStyles.Parse(value.TolerantText("style")) ?? CrestMonogramStyle.Serif),
                _ => new(CrestChargeKind.None)
            };
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// A color a record spells by name or by component, each component kept
    /// within 0 through 1 and alpha opaque unless it says.
    internal static BrandColor Color(JsonNode? node) {
        if (node is JsonValue named && named.GetValueKind() == System.Text.Json.JsonValueKind.String
            && NamedColors.TryGetValue(named.GetValue<string>(), out var color)) return color;
        var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
        return new(Unit(value.Number("red")), Unit(value.Number("green")), Unit(value.Number("blue")),
            Unit(value.OptionalNumber("alpha") ?? 1));
    }

    /// `branding` within the ranges the renderer draws, announcing the
    /// rendering vocabulary it needs and whether its controls stay readable.
    private static SpaceBranding Resolved(SpaceBranding branding) {
        var normalized = SpaceBrandingPolicy.Normalize(branding);
        return normalized with {
            KeepsControlsReadable = normalized.ReadabilityFade > 0,
            RenderingVersion = SpaceBrandingPolicy.RenderingVersion(normalized)
        };
    }

    /// A branding as every client writes it.
    private static JsonObject EncodeBranding(SpaceBranding branding) => StoredSessionCodec.Encode(branding);

    private static double Unit(double value) => Math.Clamp(value, 0, 1);

    /// A whole number a client holds in a 64-bit integer, within the range an
    /// index or a count here holds: anything outside it is out of every range.
    private static int Whole(long value) => (int)Math.Clamp(value, int.MinValue, int.MaxValue);

    #endregion
}
