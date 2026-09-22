using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Applies the core's branding rules to a Space's stored branding record in
/// place. Fields the rules do not own, including the crest's heraldic
/// vocabulary and unknown fields from newer clients, are kept as they are.
internal static class BrandingDocument {
    #region Variables

    private const string Colors = "colors";
    private const string Crest = "crest";
    private const string Palette = "palette";

    private static readonly string[] UnitFields = ["bannerStrength", "readabilityFade"];
    private static readonly string[] ColorComponents = ["red", "green", "blue", "alpha"];
    private static readonly string[] LayerIndices = [
        "backplateColorIndex", "secondaryFieldColorIndex", "ordinaryColorIndex",
        "trimColorIndex", "symbolColorIndex", "edgeColorIndex"
    ];

    /// The Space color used when a branding record has none.
    private static JsonObject DefaultColor() => new() { ["red"] = 0.29, ["green"] = 0.25, ["blue"] = 0.58, ["alpha"] = 1.0 };

    #endregion

    #region Actions - Normalization

    public static JsonObject Normalize(JsonObject branding) {
        var result = branding.DeepClone().AsObject();
        int colorCount = 1;
        if (result[Colors] is JsonArray colors) {
            var kept = colors.Take(SpaceBrandingPolicy.MaximumColorCount).Select(Color).ToList();
            if (kept.Count == 0) kept.Add(DefaultColor());
            result[Colors] = new JsonArray(kept.ToArray());
            colorCount = kept.Count;
        } else if (result[Colors] is not null) throw new ProtocolException(ProtocolErrorCodes.InvalidBranding);
        foreach (var field in UnitFields)
            if (Number(result, field) is { } value) result[field] = SpaceBrandingPolicy.Unit(value);
        if (Number(result, "gradientAngle") is { } angle) result["gradientAngle"] = SpaceBrandingPolicy.GradientAngle(angle);
        if (Number(result, "folderColorIntensity") is { } intensity) result["folderColorIntensity"] = SpaceBrandingPolicy.Unit(intensity);
        if (result["symbolColor"] is JsonObject symbolColor) result["symbolColor"] = Color(symbolColor);
        if (result[Crest] is JsonObject crest) NormalizeCrest(crest, colorCount);
        return result;
    }

    private static void NormalizeCrest(JsonObject crest, int spaceColorCount) {
        int? paletteCount = null;
        if (crest[Palette] is JsonArray palette) {
            var kept = palette.Take(SpaceBrandingPolicy.MaximumCrestPaletteCount).Select(Color).ToArray();
            if (kept.Length == 0) crest.Remove(Palette);
            else { crest[Palette] = new JsonArray(kept); paletteCount = kept.Length; }
        }
        int count = SpaceBrandingPolicy.LayerColorCount(paletteCount, spaceColorCount);
        foreach (var field in LayerIndices)
            if (crest[field] is JsonValue value && value.TryGetValue<int>(out int index))
                crest[field] = SpaceBrandingPolicy.LayerIndex(index, count);
    }

    /// A stored color object with every component kept within range. Older
    /// named colors are left for the native reader, which understands them.
    private static JsonNode? Color(JsonNode? value) {
        if (value is not JsonObject color) return value?.DeepClone();
        var result = color.DeepClone().AsObject();
        foreach (var component in ColorComponents)
            if (Number(result, component) is { } level) result[component] = SpaceBrandingPolicy.Unit(level, component == "alpha" ? 1 : 0);
        return result;
    }

    private static double? Number(JsonObject value, string field) =>
        value[field] is JsonValue number && number.TryGetValue<double>(out double result) ? result : null;

    #endregion
}
