namespace CrestCore.Contracts;

/// Where a link activation goes: in place, into Peek, or into a new tab. The
/// link-navigation policies spell a decision as its `Name`. A decision travels
/// as its index in `All`, so `All` is append-only.
public sealed class LinkNavigationDecision {
    #region Variables

    public static readonly LinkNavigationDecision Navigate = new(name: "navigate");
    public static readonly LinkNavigationDecision PeekModifier = new(name: "peekModifier", opensPeek: true);
    public static readonly LinkNavigationDecision PeekSavedSite = new(name: "peekSavedSite", opensPeek: true, protectsSavedSite: true);
    public static readonly LinkNavigationDecision BackgroundTab = new(name: "backgroundTab", opensTab: true);
    public static readonly LinkNavigationDecision ForegroundTab = new(name: "foregroundTab", opensTab: true, selectsTab: true);

    public static IReadOnlyList<LinkNavigationDecision> All { get; } =
        [Navigate, PeekModifier, PeekSavedSite, BackgroundTab, ForegroundTab];

    public string Name { get; }

    /// The link opens in Peek instead of the page.
    public bool OpensPeek { get; }

    /// Peek opens because the link leaves a saved tab's site, not because the
    /// person asked for it.
    public bool ProtectsSavedSite { get; }

    /// The link opens in a new tab.
    public bool OpensTab { get; }

    /// The new tab is selected when it opens.
    public bool SelectsTab { get; }

    #endregion

    #region Constructors

    private LinkNavigationDecision(string name, bool opensPeek = false, bool protectsSavedSite = false, bool opensTab = false,
        bool selectsTab = false) {
        Name = name;
        OpensPeek = opensPeek;
        ProtectsSavedSite = protectsSavedSite;
        OpensTab = opensTab;
        SelectsTab = selectsTab;
    }

    #endregion

    #region Actions - Lookup

    public static LinkNavigationDecision? Named(string? name) => All.FirstOrDefault(decision => decision.Name == name);

    #endregion
}
