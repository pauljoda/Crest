namespace CrestCore.Contracts;

/// The look setup gives the Spaces it makes: Crest's own banners and layered
/// crests, a modern gradient and a plain icon, or a simple sidebar in the
/// Space's one color. A look travels as its index in `All`, so `All` is
/// append-only.
public sealed class SetupLook {
    #region Types

    /// Each look is offered with a preview of its own, so the page that
    /// offers them switches over the kind.
    public enum Kinds { Heraldic, Modern, Simple }

    #endregion

    #region Static Variables

    /// A Space wears a template's banner and its layered crest.
    public static readonly SetupLook Heraldic = new(Kinds.Heraldic, name: "heraldic", title: "Heraldic (Full)", SpaceThemeMode.Banner,
        SpaceIconStyle.LayeredCrest, gradientAngle: null, tint: null, newSpaceLook: accent => accent.House);

    /// A Space wears a gradient of its colors, from top to bottom, and a
    /// plain icon.
    public static readonly SetupLook Modern = new(Kinds.Modern, name: "modern", title: "Modern", SpaceThemeMode.Gradient,
        SpaceIconStyle.SimpleSymbol, ModernGradientAngle, tint: null,
        newSpaceLook: accent => SpaceBranding.Painted(accent.LegacyColors, SpaceBannerPattern.Diagonal, strength: 1,
            SpaceBranding.LegacyReadabilityFade, SpaceThemeMode.Gradient, ModernGradientAngle, textureStrength: 0));

    /// A Space wears a plain sidebar in its accent color, and a plain icon in
    /// a shade of it that stands out from the sidebar.
    public static readonly SetupLook Simple = new(Kinds.Simple, name: "simple", title: "Simple", SpaceThemeMode.Gradient,
        SpaceIconStyle.SimpleSymbol, gradientAngle: 0, SimpleTint, newSpaceLook: accent => Simple!.Applying(accent.House));

    public static IReadOnlyList<SetupLook> All { get; } = [Heraldic, Modern, Simple];

    /// The angle a modern gradient runs at: straight down the sidebar.
    private const double ModernGradientAngle = 90;

    /// How strongly a simple sidebar wears its color over the window: fully,
    /// until the person lowers it.
    private const double SimpleTint = 1;

    /// How far an icon's shade goes toward black or white.
    private const double ContrastingShade = 0.55;

    #endregion

    #region Variables

    public Kinds Kind { get; }

    public string Name { get; }

    /// The look's name where a person picks it.
    [Localized]
    public string Title { get; }

    /// The sidebar mode a Space in this look wears.
    public SpaceThemeMode ThemeMode { get; }

    /// The icon style a Space in this look wears.
    public SpaceIconStyle IconStyle { get; }

    /// The angle a Space's gradient runs at in this look, or null for a look
    /// that keeps the Space's own.
    public double? GradientAngle { get; }

    /// The strength a Space in this look lays its one accent color at over the
    /// window, with no readability fade, or null for a look that keeps the
    /// Space's own colors.
    public double? Tint { get; }

    private readonly Func<SpaceAccent, SpaceBranding> newSpaceLook;

    #endregion

    #region Constructors

    private SetupLook(Kinds kind, string name, string title, SpaceThemeMode themeMode, SpaceIconStyle iconStyle,
        double? gradientAngle, double? tint, Func<SpaceAccent, SpaceBranding> newSpaceLook) {
        Kind = kind;
        Name = name;
        Title = title;
        ThemeMode = themeMode;
        IconStyle = iconStyle;
        GradientAngle = gradientAngle;
        Tint = tint;
        this.newSpaceLook = newSpaceLook;
    }

    #endregion

    #region Actions - Lookup

    public static SetupLook? Named(string? name) => All.FirstOrDefault(look => look.Name == name);

    #endregion

    #region Actions - Looks

    /// The look a new Space of `accent` wears.
    public SpaceBranding NewSpaceLook(SpaceAccent accent) {
        ArgumentNullException.ThrowIfNull(accent);
        return newSpaceLook(accent);
    }

    /// `branding` in this look: its sidebar mode, gradient angle and icon
    /// style, keeping its colors, crest and texture, within the ranges every
    /// device draws. A tinted look keeps only the Space's accent color, which
    /// its icon wears too.
    public SpaceBranding Applying(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        var look = branding with {
            ThemeMode = ThemeMode,
            GradientAngle = GradientAngle ?? branding.GradientAngle,
            IconStyle = IconStyle
        };
        return SpaceBranding.Normalized(Tint is { } tint ? Tinted(look, tint) : look);
    }

    /// `branding` in its one accent color at `tint`: the most vivid of its
    /// sidebar colors that is light enough to tint a sidebar and dark enough to
    /// read as an icon, or else its first. Its text reads light or dark as
    /// that color asks.
    private static SpaceBranding Tinted(SpaceBranding branding, double tint) {
        var colors = branding.Colors.Colors;
        var accent = colors.Where(color => Lightness(color) is >= 0.3 and <= 0.75).MaxBy(Chroma)
            ?? (colors.Count > 0 ? colors[0] : SpaceBranding.Neutral.Colors.Colors[0]);
        return branding with {
            Colors = new([accent]),
            BannerStrength = tint,
            ReadabilityFade = 0,
            KeepsControlsReadable = false,
            SymbolColor = Contrasting(accent),
            TextColorMode = SpaceTextColorMode.Automatic
        };
    }

    /// The shade of `color` an icon wears over it: deeper where dark text
    /// reads better on the color, paler where light text does, so the icon
    /// goes the way the Space's text does.
    private static BrandColor Contrasting(BrandColor color) {
        var toward = ReadsDark(color) ? 0.0 : 1.0;
        double Mix(double channel) => channel + (toward - channel) * ContrastingShade;
        return new(Mix(color.Red), Mix(color.Green), Mix(color.Blue), color.Alpha);
    }

    /// Whether dark text reads better than light on `color`, by APCA's
    /// lightness contrast, as the apps choose a Space's text.
    private static bool ReadsDark(BrandColor color) {
        static double Luminance(double red, double green, double blue) {
            var luminance = 0.2126729 * Math.Pow(red, 2.4) + 0.7151522 * Math.Pow(green, 2.4)
                + 0.0721750 * Math.Pow(blue, 2.4);
            return luminance < 0.022 ? luminance + Math.Pow(0.022 - luminance, 1.414) : luminance;
        }
        static double Contrast(double text, double background) {
            if (Math.Abs(background - text) < 0.0005) return 0;
            if (background > text) {
                var normal = (Math.Pow(background, 0.56) - Math.Pow(text, 0.57)) * 1.14;
                return normal < 0.1 ? 0 : normal - 0.027;
            }
            var reverse = (Math.Pow(background, 0.65) - Math.Pow(text, 0.62)) * 1.14;
            return reverse > -0.1 ? 0 : -(reverse + 0.027);
        }
        var background = Luminance(color.Red, color.Green, color.Blue);
        return Contrast(Luminance(0, 0, 0), background) > Contrast(Luminance(1, 1, 1), background);
    }

    /// How light `color` is, from 0 for black to 1 for white.
    private static double Lightness(BrandColor color) =>
        (Math.Max(color.Red, Math.Max(color.Green, color.Blue)) + Math.Min(color.Red, Math.Min(color.Green, color.Blue))) / 2;

    /// How far `color` is from gray.
    private static double Chroma(BrandColor color) =>
        Math.Max(color.Red, Math.Max(color.Green, color.Blue)) - Math.Min(color.Red, Math.Min(color.Green, color.Blue));

    /// `customization` with its look in this look.
    internal SpaceCustomization Applying(SpaceCustomization customization) {
        ArgumentNullException.ThrowIfNull(customization);
        return customization with { Branding = Applying(customization.Branding) };
    }

    #endregion
}
