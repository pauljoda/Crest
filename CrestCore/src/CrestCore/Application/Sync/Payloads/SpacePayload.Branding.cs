using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed partial record SpacePayload {
    #region Static Variables

    /// Branding stored before rendering versions were recorded is version one.
    private const int FirstRenderingVersion = 1;

    #endregion

    #region Actions - Branding

    /// A branding as every client reads it: its colors, strength and crest
    /// are required, a term a client cannot name takes its default, and every
    /// value is kept within the range the renderer draws. It keeps the
    /// rendering version it was written with, so the core's rules put a
    /// branding from before the baseline vocabulary in today's units once, and
    /// leave one already in them as it is.
    private static SpaceBranding ReadBranding(SyncPayloadReader value) {
        bool keepsReadable = value.OptionalFlag(StoredSessionCodec.Key.KeepsControlsReadable) ?? true;
        double fade = value.OptionalNumber(StoredSessionCodec.Key.ReadabilityFade) ?? (keepsReadable ? SpaceBranding.LegacyReadabilityFade : 0);
        int version = Whole(value.OptionalInteger(StoredSessionCodec.Key.RenderingVersion) ?? FirstRenderingVersion);
        var colors = value.Array(StoredSessionCodec.Key.Colors).Select(Color).ToArray();
        var branding = new SpaceBranding(new(colors),
            SpaceBannerPattern.Named(value.TolerantText(StoredSessionCodec.Key.BannerPattern)) ?? SpaceBannerPattern.Solid,
            value.Number(StoredSessionCodec.Key.BannerStrength), fade, fade > 0,
            SpaceThemeMode.Named(value.TolerantText(StoredSessionCodec.Key.ThemeMode)) ?? SpaceThemeMode.Banner,
            value.OptionalNumber(StoredSessionCodec.Key.GradientAngle) ?? 0,
            StoredSessionCodec.Texture(value.OptionalFlag(StoredSessionCodec.Key.ShowsTexture), value.TolerantNumber(StoredSessionCodec.Key.TextureStrength)),
            SpaceIconStyle.Named(value.TolerantText(StoredSessionCodec.Key.IconStyle)) ?? SpaceIconStyle.SimpleSymbol,
            value.Value[StoredSessionCodec.Key.SymbolColor] is { } symbolColor ? Color(symbolColor) : null,
            ReadCrest(value.Nested(StoredSessionCodec.Key.Crest)), version, value.TolerantNumber(StoredSessionCodec.Key.FolderColorIntensity) ?? 0,
            SpaceTextColorMode.Named(value.TolerantText(StoredSessionCodec.Key.TextColorMode)) ?? SpaceTextColorMode.Automatic,
            value.OptionalFlag(StoredSessionCodec.Key.HasCustomAppearance),
            SpaceGradientKind.Named(value.TolerantText(StoredSessionCodec.Key.GradientKind)),
            Gradient(value.Value[StoredSessionCodec.Key.SymbolGradient]), Gradients(value.Value[StoredSessionCodec.Key.ColorGradients]));
        return SpaceBranding.Normalized(branding);
    }

    /// A crest as every client reads it: each member it cannot read takes its
    /// neutral value, a figure it cannot read is none, and a palette color's
    /// gradient it cannot read is plain.
    private static SpaceCrest ReadCrest(SyncPayloadReader value) {
        int Index(string key, int fallback = 0) => Whole(value.TolerantInteger(key) ?? fallback);
        double Measure(CrestMeasure measure) => value.TolerantNumber(measure.Name) ?? measure.Default;
        int Count(CrestMeasure measure) => Whole(value.TolerantInteger(measure.Name) ?? (int)measure.Default);
        return new(CrestBackplate.Named(value.TolerantText(StoredSessionCodec.Key.Backplate)) ?? CrestBackplate.Shield,
            CrestFieldDivision.Named(value.TolerantText(StoredSessionCodec.Key.FieldDivision)) ?? CrestFieldDivision.Plain,
            CrestOrdinary.Named(value.TolerantText(StoredSessionCodec.Key.Ordinary)) ?? CrestOrdinary.None,
            CrestTrim.Named(value.TolerantText(StoredSessionCodec.Key.Trim)) ?? CrestTrim.None,
            CrestSymbol.Named(value.TolerantText(StoredSessionCodec.Key.Symbol)) ?? CrestSymbol.Fallback,
            CrestChargeLayout.Named(value.TolerantText(StoredSessionCodec.Key.ChargeLayout)) ?? CrestChargeLayout.Single,
            Index(StoredSessionCodec.Key.BackplateColorIndex), Index(StoredSessionCodec.Key.SecondaryFieldColorIndex), Index(StoredSessionCodec.Key.OrdinaryColorIndex), Index(StoredSessionCodec.Key.TrimColorIndex),
            Index(StoredSessionCodec.Key.SymbolColorIndex), value.TolerantText(StoredSessionCodec.Key.StartingPresetId), Index(StoredSessionCodec.Key.EdgeColorIndex, Index(StoredSessionCodec.Key.TrimColorIndex)),
            Palette(value.Value[StoredSessionCodec.Key.Palette]), Charge(value.Value[StoredSessionCodec.Key.Charge]),
            Measure(CrestMeasure.PlateScale), Measure(CrestMeasure.EdgeWidth), Count(CrestMeasure.DivisionCount),
            CrestFinish.Named(value.TolerantText(StoredSessionCodec.Key.Finish)) ?? CrestFinish.Flat,
            Measure(CrestMeasure.OrdinaryWidth), Measure(CrestMeasure.TrimWeight), Count(CrestMeasure.TrimDetail),
            Measure(CrestMeasure.ChargeScale), Measure(CrestMeasure.ChargeOffset),
            CrestChargeWeight.Named(value.TolerantText(StoredSessionCodec.Key.ChargeWeight)) ?? CrestChargeWeight.Bold,
            Measure(CrestMeasure.SheenAngle), Count(CrestMeasure.SealTeeth), value.TolerantFlag(StoredSessionCodec.Key.ShowsOutline) ?? false,
            CrestDepth.Named(value.TolerantText(StoredSessionCodec.Key.Depth)) ?? CrestDepth.None, Gradients(value.Value[StoredSessionCodec.Key.PaletteGradients]));
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

    /// The gradient a color runs on into, or null when it has none every client
    /// reads: colors no client reads leave it plain, a kind no client knows
    /// runs along a line, and the angle is none unless it says.
    private static BrandGradient? Gradient(JsonNode? node) {
        if (node is not JsonObject) return null;
        var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
        return new(Palette(value.Value[StoredSessionCodec.Key.Colors]) ?? new([]), SpaceGradientKind.Named(value.TolerantText(StoredSessionCodec.Key.Kind)),
            value.TolerantNumber(StoredSessionCodec.Key.Angle) ?? 0);
    }

    /// The gradients a palette's colors run on into, by index, or null when it
    /// has none every client reads. A slot no client reads is plain.
    private static PaletteGradients? Gradients(JsonNode? node) =>
        node is JsonArray slots ? new([.. slots.Select(slot => Gradient(slot) ?? BrandGradient.Plain)]) : null;

    /// A crest's custom figure, or null when it has none every client reads. A
    /// kind no client knows draws nothing; a heraldic figure no client knows is
    /// the mountain; a monogram is serif unless it says.
    private static CrestCharge? Charge(JsonNode? node) {
        if (node is not JsonObject) return null;
        try {
            var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
            string text = value.OptionalText(StoredSessionCodec.Key.Value) ?? "";
            var kind = CrestChargeKind.Named(value.TolerantText(StoredSessionCodec.Key.Kind)) ?? CrestChargeKind.None;
            return kind.Kind switch {
                CrestChargeKind.Kinds.Heraldic => new(kind, CrestSymbol.Named(text) ?? CrestSymbol.Fallback),
                CrestChargeKind.Kinds.System or CrestChargeKind.Kinds.Emoji => new(kind, Text: text),
                CrestChargeKind.Kinds.Monogram => new(kind, Text: text,
                    Style: CrestMonogramStyle.Named(value.TolerantText(StoredSessionCodec.Key.Style)) ?? CrestMonogramStyle.Serif),
                _ => new(CrestChargeKind.None)
            };
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// A color a record spells by component, or by the name of a tincture as
    /// builds before stored colors whole did, each component kept
    /// within 0 through 1 and alpha opaque unless it says.
    internal static BrandColor Color(JsonNode? node) {
        if (node is JsonValue named && named.GetValueKind() == System.Text.Json.JsonValueKind.String
            && Tincture.Named(named.GetValue<string>()) is { } tincture) return tincture.Color;
        var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
        return new(Unit(value.Number(StoredSessionCodec.Key.Red)), Unit(value.Number(StoredSessionCodec.Key.Green)), Unit(value.Number(StoredSessionCodec.Key.Blue)),
            Unit(value.OptionalNumber(StoredSessionCodec.Key.Alpha) ?? 1));
    }

    /// A branding as every client writes it.
    private static JsonObject EncodeBranding(SpaceBranding branding) => StoredSessionCodec.Encode(branding);

    private static double Unit(double value) => Math.Clamp(value, 0, 1);

    /// A whole number a client holds in a 64-bit integer, within the range an
    /// index or a count here holds: anything outside it is out of every range.
    private static int Whole(long value) => (int)Math.Clamp(value, int.MinValue, int.MaxValue);

    #endregion
}
