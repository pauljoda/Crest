namespace CrestCore.Contracts;

/// A kind of thing Crest's filter lists keep off a page, as Site Controls name
/// what a site is spared. A list blocks one kind or more; one that only fixes
/// what the others break, such as uBlock's quick fixes, blocks none.
///
/// A kind travels as its index in `All`, so `All` is append-only.
public sealed class ContentBlockKind {
    #region Static Variables

    public static readonly ContentBlockKind Ads = new(name: "ads", title: "Ads", symbol: "megaphone");
    public static readonly ContentBlockKind Trackers = new(name: "trackers", title: "Trackers", symbol: "eye.slash");
    public static readonly ContentBlockKind Scams = new(name: "scams", title: "Scams", symbol: "exclamationmark.shield");
    public static readonly ContentBlockKind CookieNotices = new(name: "cookie-notices", title: "Cookie notices",
        symbol: "checklist");
    public static readonly ContentBlockKind Annoyances = new(name: "annoyances", title: "Annoyances", symbol: "bell.slash");

    public static IReadOnlyList<ContentBlockKind> All { get; } = [Ads, Trackers, Scams, CookieNotices, Annoyances];

    #endregion

    #region Variables

    public string Name { get; }

    /// What Site Controls call the kind.
    [Localized]
    public string Title { get; }

    /// The SF Symbol Site Controls show beside it.
    public string Symbol { get; }

    #endregion

    #region Constructors

    private ContentBlockKind(string name, string title, string symbol) {
        Name = name;
        Title = title;
        Symbol = symbol;
    }

    #endregion
}
