namespace CrestCore.Contracts;

/// How a page with no tab presents: a Peek over the tab it opened from, a
/// Quick Window of its own, or one of its engine's own pages, such as its
/// feature flags, inside Settings. A presentation travels as its index in
/// `All`, so `All` is append-only.
public sealed class TransientPresentation {
    #region Variables

    /// A link a Peek opens in a new tab comes to the front, since the Peek is
    /// what the person is looking at.
    public static readonly TransientPresentation Peek = new(name: "peek", opensNewTabsInFront: true);

    /// A link a Quick Window opens in a new tab follows the person's link
    /// preferences, and a page it opens in a new window opens a Quick Window
    /// of its own.
    public static readonly TransientPresentation QuickWindow = new(name: "quickWindow", opensNewTabsInFront: false,
        opensPagesAsWindows: true);

    /// A link an engine's own page in Settings opens in a new tab follows the
    /// person's link preferences.
    public static readonly TransientPresentation Settings = new(name: "settings", opensNewTabsInFront: false);

    public static IReadOnlyList<TransientPresentation> All { get; } = [Peek, QuickWindow, Settings];

    public string Name { get; }

    /// A link the page opens in a new tab always comes to the front.
    public bool OpensNewTabsInFront { get; }

    /// A page the page opens in a new window, as a `target="_blank"` link or
    /// `window.open` does, opens as a Quick Window of its own beside it rather
    /// than loading in the page. Only the core reads it.
    internal bool OpensPagesAsWindows { get; }

    #endregion

    #region Constructors

    private TransientPresentation(string name, bool opensNewTabsInFront, bool opensPagesAsWindows = false) {
        Name = name;
        OpensNewTabsInFront = opensNewTabsInFront;
        OpensPagesAsWindows = opensPagesAsWindows;
    }

    #endregion

    #region Actions - Lookup

    public static TransientPresentation? Named(string? name) => All.FirstOrDefault(presentation => presentation.Name == name);

    #endregion
}
