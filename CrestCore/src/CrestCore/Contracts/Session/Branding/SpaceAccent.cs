namespace CrestCore.Contracts;

/// The accent a Space was made with: the house look a new Space of the accent
/// wears, the look a Space stored before branding existed wears, and the
/// swatch a color from elsewhere is matched against.
///
/// The stored session and synced Space records spell an accent as its `Name`,
/// so a name never changes. An accent travels as its index in `All`, so `All`
/// is append-only.
public sealed class SpaceAccent {
    #region Static Variables

    /// Crest, the look a first Space wears.
    public static readonly SpaceAccent Indigo = new(name: "indigo",
        legacyColors: [Tincture.Ink, Tincture.Ocean, Tincture.Gold], house: SpaceHouse.Crest.Look, swatch: Tincture.Indigo);
    /// Sun.
    public static readonly SpaceAccent Orange = new(name: "orange",
        legacyColors: [Tincture.Ember, Tincture.Gold, Tincture.Ocean], house: SpaceHouse.Sun.Look, swatch: Tincture.Ember);
    /// Meadow.
    public static readonly SpaceAccent Teal = new(name: "teal",
        legacyColors: [Tincture.Teal, Tincture.Ocean, Tincture.Sand], house: SpaceHouse.Meadow.Look, swatch: Tincture.Teal);
    /// Lion.
    public static readonly SpaceAccent Rose = new(name: "rose",
        legacyColors: [Tincture.Rose, Tincture.Indigo, Tincture.Sand], house: SpaceHouse.Lion.Look, swatch: Tincture.Rose);

    public static IReadOnlyList<SpaceAccent> All { get; } = [Indigo, Orange, Teal, Rose];

    #endregion

    #region Variables

    public string Name { get; }

    /// The palette a Space stored before branding existed wears: its
    /// background, primary and secondary color.
    public IReadOnlyList<BrandColor> LegacyColors { get; }

    /// The house look a new Space of this accent wears: a deep Background and a
    /// luminous Accent, either of which may be a gradient, a Pattern a step
    /// above the Background, and the house's arms, which follow those colors.
    /// A Space keeps its copy when this changes.
    public SpaceBranding House { get; }

    /// The one color that stands for the accent, which a color from elsewhere,
    /// such as another browser's Space, is matched against.
    public BrandColor Swatch { get; }

    #endregion

    #region Constructors

    private SpaceAccent(string name, IReadOnlyList<Tincture> legacyColors, SpaceBranding house, Tincture swatch) {
        Name = name;
        LegacyColors = [.. legacyColors.Select(tincture => tincture.Color)];
        House = house;
        Swatch = swatch.Color;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceAccent? Named(string? name) => All.FirstOrDefault(accent => accent.Name == name);

    /// The accent whose swatch lies nearest `color` in red, green and blue,
    /// the first in `All` on a tie.
    public static SpaceAccent Nearest(BrandColor color) {
        ArgumentNullException.ThrowIfNull(color);
        return All.MinBy(accent => Math.Pow(color.Red - accent.Swatch.Red, 2) + Math.Pow(color.Green - accent.Swatch.Green, 2)
            + Math.Pow(color.Blue - accent.Swatch.Blue, 2))!;
    }

    #endregion
}
