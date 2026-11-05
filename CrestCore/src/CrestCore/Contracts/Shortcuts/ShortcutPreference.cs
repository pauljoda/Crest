namespace CrestCore.Contracts;

/// Who answers a command's keys while a page with focus uses them too: Crest
/// before the page sees them, the page first and Crest on a quick second
/// press, or the page alone, with Crest running the command only when the page
/// lets the keys go.
///
/// Each command has one by default, and a person may choose another for a
/// command that does not keep its own. The device store keeps a choice as its
/// `Name`, so a name never changes. `All` is append-only, and its order is the
/// order a choice lists them in.
public sealed class ShortcutPreference {
    #region Variables

    public static readonly ShortcutPreference PreferCrest = new(name: "preferCrest", title: "Prefer Crest", symbol: "macwindow",
        runsBeforePage: true, takesSecondPress: false);
    public static readonly ShortcutPreference UseBoth = new(name: "useBoth", title: "Use Both", symbol: "2.circle",
        runsBeforePage: false, takesSecondPress: true);
    public static readonly ShortcutPreference PreferWebsite = new(name: "preferWebsite", title: "Prefer Website", symbol: "globe",
        runsBeforePage: false, takesSecondPress: false);

    public static IReadOnlyList<ShortcutPreference> All { get; } = [PreferCrest, UseBoth, PreferWebsite];

    public string Name { get; }

    /// What the shortcut settings call the preference.
    [Localized]
    public string Title { get; }

    /// The SF Symbol shown beside the preference.
    public string Symbol { get; }

    /// Whether Crest runs the command before a focused page sees its keys.
    public bool RunsBeforePage { get; }

    /// Whether a second press of the keys a page kept runs the command, before
    /// the page sees that press.
    public bool TakesSecondPress { get; }

    #endregion

    #region Constructors

    private ShortcutPreference(string name, string title, string symbol, bool runsBeforePage, bool takesSecondPress) {
        Name = name;
        Title = title;
        Symbol = symbol;
        RunsBeforePage = runsBeforePage;
        TakesSecondPress = takesSecondPress;
    }

    #endregion

    #region Actions - Lookup

    public static ShortcutPreference? Named(string? name) => All.FirstOrDefault(preference => preference.Name == name);

    #endregion
}
