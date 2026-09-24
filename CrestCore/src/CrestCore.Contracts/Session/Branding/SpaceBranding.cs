namespace CrestCore.Contracts;

/// <summary>
/// How a Space's sidebar and icon look. <see cref="RenderingVersion"/> is the newest
/// vocabulary the branding uses, which older readers need to read it faithfully.
/// <see cref="HasCustomAppearance"/> is null for branding stored before it was recorded.
/// </summary>
public sealed record SpaceBranding(
    ColorPalette Colors,
    SpaceBannerPattern BannerPattern,
    double BannerStrength,
    double ReadabilityFade,
    bool KeepsControlsReadable,
    SpaceThemeMode ThemeMode,
    double GradientAngle,
    bool ShowsTexture,
    SpaceIconStyle IconStyle,
    BrandColor? SymbolColor,
    SpaceCrest Crest,
    int RenderingVersion,
    double FolderColorIntensity,
    SpaceTextColorMode TextColorMode,
    bool? HasCustomAppearance);
