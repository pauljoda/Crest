namespace CrestCore.Contracts;

/// Which pages open with the developer toolbar showing: none, local pages, or
/// every website. The stored preferences spell a mode as its `Name`, so a name
/// never changes. A mode travels as its index in `All`, so `All` is
/// append-only.
public sealed class DeveloperToolbarMode {
    #region Variables

    public static readonly DeveloperToolbarMode Off = new(name: "off", title: "Off");

    public static readonly DeveloperToolbarMode LocalPages = new(name: "localPages", title: "On local pages");

    public static readonly DeveloperToolbarMode AllWebsites = new(name: "allWebsites", title: "On all websites");

    public static IReadOnlyList<DeveloperToolbarMode> All { get; } = [Off, LocalPages, AllWebsites];

    public string Name { get; }

    /// What the developer toolbar setting calls the mode.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private DeveloperToolbarMode(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static DeveloperToolbarMode? Named(string? name) => All.FirstOrDefault(mode => mode.Name == name);

    #endregion
}
