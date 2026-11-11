namespace CrestCore.Contracts;

/// What a new window shows first: the Start Page, the tab that was active
/// when Crest last quit, a new tab in the default Space, ready to search, or
/// search over the tab that was active.
/// The stored preferences spell a behavior as its `Name`, so a name never
/// changes. A behavior travels as its index in `All`, so `All` is append-only.
public sealed class StartupBehavior {
    #region Variables

    public static readonly StartupBehavior ShowStartPage = new(name: "showStartPage", title: "Show Start Page",
        activatesRestoredTab: false, opensNewTab: false, presentsSearch: false);

    public static readonly StartupBehavior LastActiveTab = new(name: "lastActiveTab", title: "Open Last Active Tab",
        activatesRestoredTab: true, opensNewTab: false, presentsSearch: false);

    public static readonly StartupBehavior NewTab = new(name: "newTab", title: "Open a New Tab",
        activatesRestoredTab: false, opensNewTab: true, presentsSearch: false);

    public static readonly StartupBehavior Search = new(name: "search", title: "Open Search",
        activatesRestoredTab: true, opensNewTab: false, presentsSearch: true);

    public static IReadOnlyList<StartupBehavior> All { get; } = [ShowStartPage, LastActiveTab, NewTab, Search];

    public string Name { get; }

    /// What the General settings call the choice.
    [Localized]
    public string Title { get; }

    /// A window opens on the tab it restores, rather than in front of it.
    public bool ActivatesRestoredTab { get; }

    /// A window opens a new tab in the default Space, with the address field
    /// ready to type in.
    public bool OpensNewTab { get; }

    /// A window opens on the tab it restores with search ready over it, and
    /// offers search again when the person comes back after a while away.
    /// What they open from it goes to a new tab, leaving that tab behind.
    public bool PresentsSearch { get; }

    #endregion

    #region Constructors

    private StartupBehavior(string name, string title, bool activatesRestoredTab, bool opensNewTab,
        bool presentsSearch) {
        Name = name;
        Title = title;
        ActivatesRestoredTab = activatesRestoredTab;
        OpensNewTab = opensNewTab;
        PresentsSearch = presentsSearch;
    }

    #endregion

    #region Actions - Lookup

    public static StartupBehavior? Named(string? name) => All.FirstOrDefault(behavior => behavior.Name == name);

    #endregion
}
