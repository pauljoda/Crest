namespace CrestCore.Contracts;

/// The key a person holds while clicking a link to open it in Peek. Command
/// then opens the link in a new tab, or Option when Command opens Peek.
///
/// Link preferences (`crest.link-preferences.v1`) and the link-navigation
/// policy spell a modifier as its `Name`, so a name never changes.
public sealed class LinkPeekModifier {
    #region Variables

    public static readonly LinkPeekModifier Option = new(name: "option", title: "Option (⌥)", clickTitle: "Option-click",
        peekKey: ShortcutModifiers.Option, newTabKey: ShortcutModifiers.Command, yieldsToNewTabKey: false);
    public static readonly LinkPeekModifier Command = new(name: "command", title: "Command (⌘)", clickTitle: "Command-click",
        peekKey: ShortcutModifiers.Command, newTabKey: ShortcutModifiers.Option, yieldsToNewTabKey: false);
    /// Shift also says which way a new tab opens, so Command-Shift-click
    /// still opens one.
    public static readonly LinkPeekModifier Shift = new(name: "shift", title: "Shift (⇧)", clickTitle: "Shift-click",
        peekKey: ShortcutModifiers.Shift, newTabKey: ShortcutModifiers.Command, yieldsToNewTabKey: true);

    public static IReadOnlyList<LinkPeekModifier> All { get; } = [Option, Command, Shift];

    public string Name { get; }

    /// What the link settings call the modifier.
    [Localized]
    public string Title { get; }

    /// The click the link settings' guidance names.
    [Localized]
    public string ClickTitle { get; }

    /// The key that opens a clicked link in Peek.
    public ShortcutModifiers PeekKey { get; }

    /// The key that opens a clicked link in a new tab.
    public ShortcutModifiers NewTabKey { get; }

    /// Whether the new-tab key held with this one opens a new tab rather than
    /// Peek, because this key also says which way a new tab opens.
    public bool YieldsToNewTabKey { get; }

    #endregion

    #region Constructors

    private LinkPeekModifier(string name, string title, string clickTitle, ShortcutModifiers peekKey, ShortcutModifiers newTabKey,
        bool yieldsToNewTabKey) {
        Name = name;
        Title = title;
        ClickTitle = clickTitle;
        PeekKey = peekKey;
        NewTabKey = newTabKey;
        YieldsToNewTabKey = yieldsToNewTabKey;
    }

    #endregion

    #region Actions - Lookup

    public static LinkPeekModifier? Named(string? name) => All.FirstOrDefault(modifier => modifier.Name == name);

    #endregion

    #region Actions - Clicks

    /// What a click with `held` keys asks for. Peek wins over the new-tab key
    /// when both are held, unless this key yields to it, and a middle click
    /// always asks for a new tab.
    public (bool Peek, bool NewTab) Intent(ShortcutModifiers held, bool isMiddleClick) {
        bool peek = held.HasFlag(PeekKey) && !(YieldsToNewTabKey && held.HasFlag(NewTabKey));
        return (peek, (!peek && held.HasFlag(NewTabKey)) || isMiddleClick);
    }

    #endregion
}
