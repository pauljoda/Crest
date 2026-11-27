namespace CrestCore.Contracts;

/// A native view a tab shows in place of a web page, which the platform
/// draws: its `Name`, which a tab's native content keeps as its kind
/// (`NativeTabContent.Kind`), the title and symbol a tab that shows it
/// takes when it opens, the section that tab opens in, and whether a Space
/// keeps one such tab, which opening it again shows. A kind another build
/// added keeps its name in the session and has no member here. A view
/// travels as its index in `All`, so `All` is append-only.
public sealed class NativeView {
    #region Static Variables

    public static readonly NativeView Settings = new(name: "settings", title: "Settings", symbol: "gearshape.fill",
        TabPlacement.Current, opensOnce: true);

    public static readonly NativeView GettingStarted = new(name: "getting-started", title: "Getting Started",
        symbol: "book.closed.fill", TabPlacement.Saved, opensOnce: true);

    public static IReadOnlyList<NativeView> All { get; } = [Settings, GettingStarted];

    #endregion

    #region Variables

    /// The kind a tab's native content keeps in the stored session and in
    /// sync, so a name never changes.
    public string Name { get; }

    /// What a tab showing the view is called until the person renames it.
    [Localized]
    public string Title { get; }

    /// The SF Symbol a tab showing the view wears until the person chooses
    /// another.
    public string Symbol { get; }

    /// The section a tab opened to show the view goes in.
    public TabPlacement Placement { get; }

    /// Whether a Space keeps one tab showing the view, which opening the view
    /// again shows instead of opening another.
    public bool OpensOnce { get; }

    #endregion

    #region Constructors

    private NativeView(string name, string title, string symbol, TabPlacement placement, bool opensOnce) {
        Name = name;
        Title = title;
        Symbol = symbol;
        Placement = placement;
        OpensOnce = opensOnce;
    }

    #endregion

    #region Actions - Lookup

    public static NativeView? Named(string? name) => All.FirstOrDefault(view => view.Name == name);

    #endregion
}
