namespace CrestCore.Contracts;

/// How a page with no tab presents: a Peek over the tab it opened from, a
/// Quick Window of its own, or one of its engine's own pages, such as its
/// feature flags, inside Settings. A presentation travels as its index in
/// `All`, so `All` is append-only.
public sealed class TransientPresentation {
    #region Variables

    /// A link a Peek opens in a new tab comes to the front, since the Peek is
    /// what the person is looking at.
    public static readonly TransientPresentation Peek = new(name: "peek", opensNewTabsInFront: true, keptAs: TabOpening.Link);

    /// A link a Quick Window opens in a new tab follows the person's link
    /// preferences.
    public static readonly TransientPresentation QuickWindow = new(name: "quickWindow", opensNewTabsInFront: false,
        keptAs: TabOpening.NewTab);

    /// A link an engine's own page in Settings opens in a new tab follows the
    /// person's link preferences.
    public static readonly TransientPresentation Settings = new(name: "settings", opensNewTabsInFront: false,
        keptAs: TabOpening.NewTab);

    public static IReadOnlyList<TransientPresentation> All { get; } = [Peek, QuickWindow, Settings];

    public string Name { get; }

    /// A link the page opens in a new tab always comes to the front.
    public bool OpensNewTabsInFront { get; }

    /// How the tab that keeps the page opens: a kept Peek is a tab from a
    /// link, and any other page a new tab.
    internal TabOpening KeptAs { get; }

    #endregion

    #region Constructors

    private TransientPresentation(string name, bool opensNewTabsInFront, TabOpening keptAs) {
        Name = name;
        OpensNewTabsInFront = opensNewTabsInFront;
        KeptAs = keptAs;
    }

    #endregion

    #region Actions - Lookup

    public static TransientPresentation? Named(string? name) => All.FirstOrDefault(presentation => presentation.Name == name);

    #endregion
}
