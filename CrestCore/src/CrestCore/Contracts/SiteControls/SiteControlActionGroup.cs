namespace CrestCore.Contracts;

/// A group of Site Controls' actions, as More Actions and the list the four
/// are chosen from show them. Groups are listed in `All` order.
public sealed class SiteControlActionGroup {
    #region Static Variables

    public static readonly SiteControlActionGroup Copy = new(name: "copy", title: "Copy");
    public static readonly SiteControlActionGroup ShareAndExport = new(name: "shareAndExport", title: "Share and Export");
    public static readonly SiteControlActionGroup Tab = new(name: "tab", title: "Tab");
    public static readonly SiteControlActionGroup Page = new(name: "page", title: "Page");
    public static readonly SiteControlActionGroup Browser = new(name: "browser", title: "Browser");
    public static readonly SiteControlActionGroup Privacy = new(name: "privacy", title: "Privacy");
    public static readonly SiteControlActionGroup Developer = new(name: "developer", title: "Developer");

    public static IReadOnlyList<SiteControlActionGroup> All { get; } = [Copy, ShareAndExport, Tab, Page, Browser, Privacy, Developer];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the group's caps label says.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SiteControlActionGroup(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SiteControlActionGroup? Named(string? name) => All.FirstOrDefault(group => group.Name == name);

    #endregion
}
