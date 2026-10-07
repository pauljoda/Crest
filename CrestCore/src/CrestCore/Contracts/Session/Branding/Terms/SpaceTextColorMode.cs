namespace CrestCore.Contracts;

/// Whether sidebar text follows the banner or stays light or dark.
public sealed class SpaceTextColorMode {
    #region Types

    /// Each platform maps each mode to its own text tone, so the code that picks the tone switches over the kind.
    public enum Kinds { Automatic, Light, Dark }

    #endregion

    #region Variables

    public static readonly SpaceTextColorMode Automatic = new(Kinds.Automatic, "automatic", "Automatic");
    public static readonly SpaceTextColorMode Light = new(Kinds.Light, "light", "Light");
    public static readonly SpaceTextColorMode Dark = new(Kinds.Dark, "dark", "Dark");

    public static IReadOnlyList<SpaceTextColorMode> All { get; } = [Automatic, Light, Dark];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The choice's name where a person picks it.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SpaceTextColorMode(Kinds kind, string name, string title) {
        Kind = kind;
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceTextColorMode? Named(string? name) => All.FirstOrDefault(mode => mode.Name == name);

    #endregion
}
