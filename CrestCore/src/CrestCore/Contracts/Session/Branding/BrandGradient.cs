namespace CrestCore.Contracts;

/// <summary>A color that runs on into more. <see cref="Colors"/> are the one or two
/// colors after the base color, which stays where the branding keeps it.
/// <see cref="Kind"/> is how the gradient runs, or null for along a line at
/// <see cref="Angle"/>, in degrees from 0 for left to right to 90 for top to
/// bottom. A gradient with no colors is plain: the base color alone.</summary>
public sealed record BrandGradient(ColorPalette Colors, SpaceGradientKind? Kind, double Angle) {
    #region Static Variables

    /// The gradient of a color that runs on into nothing.
    internal static BrandGradient Plain { get; } = new(new([]), Kind: null, Angle: 0);

    #endregion

    #region Variables

    /// Whether the color runs on into nothing, so it draws as the base color alone.
    internal bool IsPlain => Colors.Colors.Count == 0;

    #endregion
}
