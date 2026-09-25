namespace CrestCore.Contracts;

/// The accent a Space shows in places too small for its branding: the system
/// color it tints small marks with, the house look a new Space of the accent
/// wears, and the look a Space stored before branding existed wears.
///
/// The stored session and synced Space records spell an accent as its `Name`,
/// so a name never changes. An accent travels as its index in `All`, so `All`
/// is append-only.
public sealed class SpaceAccent {
    #region Static Variables

    // The named palette colors a Space wore before branding existed.
    private static readonly BrandColor Ink = new(0.08, 0.15, 0.23);
    private static readonly BrandColor IndigoColor = new(0.29, 0.25, 0.58);
    private static readonly BrandColor Ocean = new(0.22, 0.42, 0.64);
    private static readonly BrandColor TealColor = new(0.12, 0.49, 0.52);
    private static readonly BrandColor Gold = new(0.88, 0.67, 0.25);
    private static readonly BrandColor Ember = new(0.85, 0.27, 0.20);
    private static readonly BrandColor RoseColor = new(0.72, 0.25, 0.42);
    private static readonly BrandColor Sand = new(0.82, 0.72, 0.56);

    /// Winter.
    public static readonly SpaceAccent Indigo = new(name: "indigo", tint: SystemTint.Indigo, legacyColors: [Ink, Ocean, Gold],
        house: HouseLook([new(0.118, 0.157, 0.200), new(0.243, 0.306, 0.369), new(0.525, 0.678, 0.769)], CrestBackplate.FrenchShield,
            CrestSymbol.Direwolf, CrestTrim.Line));
    /// Sun.
    public static readonly SpaceAccent Orange = new(name: "orange", tint: SystemTint.Orange, legacyColors: [Ember, Gold, Ocean],
        house: HouseLook([new(0.208, 0.086, 0.043), new(0.545, 0.239, 0.106), new(0.816, 0.620, 0.396)], CrestBackplate.Circle,
            CrestSymbol.Sun, CrestTrim.Sunburst));
    /// Meadow.
    public static readonly SpaceAccent Teal = new(name: "teal", tint: SystemTint.Teal, legacyColors: [TealColor, Ocean, Sand],
        house: HouseLook([new(0.082, 0.137, 0.094), new(0.204, 0.341, 0.220), new(0.737, 0.655, 0.400)], CrestBackplate.Circle,
            CrestSymbol.Rose, CrestTrim.Laurel));
    /// Lion.
    public static readonly SpaceAccent Rose = new(name: "rose", tint: SystemTint.Pink, legacyColors: [RoseColor, IndigoColor, Sand],
        house: HouseLook([new(0.235, 0.055, 0.102), new(0.447, 0.125, 0.188), new(0.788, 0.635, 0.329)], CrestBackplate.Shield,
            CrestSymbol.Lion, CrestTrim.Line));

    public static IReadOnlyList<SpaceAccent> All { get; } = [Indigo, Orange, Teal, Rose];

    #endregion

    #region Variables

    public string Name { get; }

    /// The system color the accent tints small marks with.
    public SystemTint Tint { get; }

    /// The palette a Space stored before branding existed wears: its
    /// background, primary and secondary color.
    public IReadOnlyList<BrandColor> LegacyColors { get; }

    /// The house look a new Space of this accent wears: a deep field, a related
    /// tincture a step above it and one luminous charge, with the crest
    /// composed for it. A Space keeps its copy when this changes.
    public SpaceBranding House { get; }

    #endregion

    #region Constructors

    private SpaceAccent(string name, SystemTint tint, IReadOnlyList<BrandColor> legacyColors, SpaceBranding house) {
        Name = name;
        Tint = tint;
        LegacyColors = legacyColors;
        House = house;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceAccent? Named(string? name) => All.FirstOrDefault(accent => accent.Name == name);

    #endregion

    #region Actions - Looks

    /// A house palette's branding: a diagonal banner that keeps controls
    /// readable, and the layered crest drawn in the palette's own colors.
    private static SpaceBranding HouseLook(BrandColor[] colors, CrestBackplate backplate, CrestSymbol figure, CrestTrim trim) =>
        new(new(colors), SpaceBannerPattern.Diagonal, BannerStrength: 1, ReadabilityFade: 0.45, KeepsControlsReadable: true,
            SpaceThemeMode.Banner, GradientAngle: 0, ShowsTexture: false, SpaceIconStyle.LayeredCrest, SymbolColor: null,
            SpaceCrest.PlainField(backplate, figure, trim, layers: [0, 1, 1, 2, 2, 2], trimWeight: 0.75, chargeScale: 1.2),
            RenderingVersion: 5, FolderColorIntensity: 0, SpaceTextColorMode.Automatic, HasCustomAppearance: false);

    #endregion
}
