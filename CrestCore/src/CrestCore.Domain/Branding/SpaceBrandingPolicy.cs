namespace CrestCore.Domain;

/// Range rules for a Space's banner branding. The crest's heraldic vocabulary
/// and its composition parameters stay with the native renderer; the core owns
/// the palette size, the banner strengths, the gradient angle and the crest's
/// layer colors pointing at a color that exists.
public static class SpaceBrandingPolicy {
    #region Variables

    public const int MaximumColorCount = 3;
    public const int MaximumCrestPaletteCount = 4;

    #endregion

    #region Actions - Normalization

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

    #endregion
}
