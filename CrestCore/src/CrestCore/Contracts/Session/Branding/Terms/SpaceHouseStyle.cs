namespace CrestCore.Contracts;

/// How a house's crest is drawn, which the gallery groups the houses by:
/// simple, a bold rounded figure on a soft shape in Crest's own colors, or
/// heraldic, full arms in the colors of the house.
public sealed class SpaceHouseStyle {
    #region Static Variables

    public static readonly SpaceHouseStyle Simple = new("simple", "Simple");
    public static readonly SpaceHouseStyle Heraldic = new("heraldic", "Heraldic");

    public static IReadOnlyList<SpaceHouseStyle> All { get; } = [Simple, Heraldic];

    #endregion

    #region Variables

    public string Name { get; }

    /// The style's name over its houses in the gallery.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SpaceHouseStyle(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceHouseStyle? Named(string? name) => All.FirstOrDefault(style => style.Name == name);

    #endregion
}
