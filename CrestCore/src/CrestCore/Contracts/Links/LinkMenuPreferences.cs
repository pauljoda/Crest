namespace CrestCore.Contracts;

#region Types

/// One of Crest's rows in a page's context menu and whether the menu shows
/// it. In `LinkMenuPreferences.Rows` their order is the menu's.
public sealed record LinkMenuChoice(LinkMenuRow Row, bool IsShown);

#endregion

/// Which of Crest's rows a page's context menu shows for a link or a selected
/// text, and in what order, ahead of the engine's own items. This device keeps
/// them among its app-wide preferences and never syncs them.
public sealed record LinkMenuPreferences(IReadOnlyList<LinkMenuChoice> Rows) {
    #region Static Variables

    /// What a person who never chose sees: every row, in its default order.
    public static LinkMenuPreferences Default { get; } =
        new([.. LinkMenuRow.All.Select(row => new LinkMenuChoice(row, IsShown: true))]);

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<LinkMenuChoice> Rows {
        get;
        init => field = [.. value];
    } = [.. Rows];

    #endregion

    #region Actions - Restoring

    /// These preferences with every row named exactly once: a row repeated
    /// keeps its first place, and a row they never named, such as one a later
    /// release added, joins after the others and shows.
    public LinkMenuPreferences Restored() {
        List<LinkMenuChoice> restored = [];
        foreach (var choice in Rows)
            if (restored.All(kept => kept.Row != choice.Row)) restored.Add(choice);
        foreach (var row in LinkMenuRow.All)
            if (restored.All(kept => kept.Row != row)) restored.Add(new(row, IsShown: true));
        return this with { Rows = restored };
    }

    #endregion

    #region Actions - Equality

    /// Equal when they name the same rows, in the same order, each shown or hidden alike.
    public bool Equals(LinkMenuPreferences? other) => other is not null && Rows.SequenceEqual(other.Rows);

    /// Hashes by the number of rows, which equal preferences share.
    public override int GetHashCode() => Rows.Count;

    #endregion
}

/// One of the rows Crest puts in a page's context menu. The stored preferences
/// spell a row as its `Name`, so a name never changes. A row travels as its
/// index in `All`, so `All` is append-only.
public sealed class LinkMenuRow {
    #region Static Variables

    public static readonly LinkMenuRow NewTab = new(name: "newTab", title: "Open Link in New Tab");
    public static readonly LinkMenuRow Peek = new(name: "peek", title: "Open Link in Peek");
    public static readonly LinkMenuRow SplitView = new(name: "splitView", title: "Open Link in Split View");
    public static readonly LinkMenuRow OtherSpaces = new(name: "otherSpaces", title: "Open Link in Another Space");
    public static readonly LinkMenuRow Search = new(name: "search", title: "Search with Selection");

    /// The rows, in the order a person who never chose sees them.
    public static IReadOnlyList<LinkMenuRow> All { get; } = [NewTab, Peek, SplitView, OtherSpaces, Search];

    #endregion

    #region Variables

    /// The row's stored spelling, which never changes.
    public string Name { get; }

    /// What the settings call the row.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    /// A row stored as `name` that the settings call `title`.
    private LinkMenuRow(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    /// The row stored as `name`, or null for one this build does not know.
    public static LinkMenuRow? Named(string? name) => All.FirstOrDefault(row => row.Name == name);

    #endregion
}
