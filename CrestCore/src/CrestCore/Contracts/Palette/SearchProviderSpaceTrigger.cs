namespace CrestCore.Contracts;

/// How Space after a provider shortcut enters its search. Stored names stay stable;
/// the generated wire tag follows this append-only order.
public sealed class SearchProviderSpaceTrigger {
    #region Static Variables

    public static readonly SearchProviderSpaceTrigger Off = new("off", "Off", "Space keeps typing normally.", false, false);
    public static readonly SearchProviderSpaceTrigger PrefixedShortcut = new("prefixedShortcut", "Require $ before shortcut",
        "Example: $yt, then Space", true, true);
    public static readonly SearchProviderSpaceTrigger Shortcut = new("shortcut", "Shortcut without $",
        "Example: yt, then Space", true, false);
    public static IReadOnlyList<SearchProviderSpaceTrigger> All { get; } = [Off, PrefixedShortcut, Shortcut];

    #endregion

    #region Variables

    public string Name { get; }
    [Localized]
    public string Title { get; }
    [Localized]
    public string Example { get; }
    public bool IsEnabled { get; }
    public bool RequiresPrefix { get; }

    #endregion

    #region Constructors

    private SearchProviderSpaceTrigger(string name, string title, string example, bool isEnabled, bool requiresPrefix) {
        Name = name;
        Title = title;
        Example = example;
        IsEnabled = isEnabled;
        RequiresPrefix = requiresPrefix;
    }

    #endregion

    #region Actions - Triggers

    /// The shortcut the word names, or null when this mode does not accept it.
    public string? ShortcutFrom(string word, char sign) {
        if (!IsEnabled) return null;
        if (word.StartsWith(sign)) return word.Length > 1 ? word[1..] : null;
        return RequiresPrefix ? null : word;
    }

    public static SearchProviderSpaceTrigger? Named(string? name) => All.FirstOrDefault(mode => mode.Name == name);

    #endregion
}
