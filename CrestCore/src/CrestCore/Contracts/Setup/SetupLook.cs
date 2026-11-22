namespace CrestCore.Contracts;

/// The look setup gives the Spaces it makes: Crest's own banners and layered
/// crests. A look travels as its index in `All`, so `All` is append-only.
public sealed class SetupLook {
    #region Static Variables

    /// A Space wears a template's banner and its layered crest.
    public static readonly SetupLook Heraldic = new(name: "heraldic", title: "Heraldic (Full)", SpaceThemeMode.Banner,
        SpaceIconStyle.LayeredCrest, newSpaceLook: accent => accent.House);

    public static IReadOnlyList<SetupLook> All { get; } = [Heraldic];

    #endregion

    #region Variables

    public string Name { get; }

    /// The look's name where a person picks it.
    [Localized]
    public string Title { get; }

    /// The sidebar mode a Space in this look wears.
    public SpaceThemeMode ThemeMode { get; }

    /// The icon style a Space in this look wears.
    public SpaceIconStyle IconStyle { get; }

    private readonly Func<SpaceAccent, SpaceBranding> newSpaceLook;

    #endregion

    #region Constructors

    private SetupLook(string name, string title, SpaceThemeMode themeMode, SpaceIconStyle iconStyle,
        Func<SpaceAccent, SpaceBranding> newSpaceLook) {
        Name = name;
        Title = title;
        ThemeMode = themeMode;
        IconStyle = iconStyle;
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

    /// `branding` in this look: its sidebar mode and icon style, keeping its
    /// colors, the gradients they run on into, crest and texture, within the
    /// ranges every device draws.
    public SpaceBranding Applying(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        return SpaceBranding.Normalized(branding with { ThemeMode = ThemeMode, IconStyle = IconStyle });
    }

    /// `customization` with its look in this look.
    internal SpaceCustomization Applying(SpaceCustomization customization) {
        ArgumentNullException.ThrowIfNull(customization);
        return customization with { Branding = Applying(customization.Branding) };
    }

    #endregion
}
