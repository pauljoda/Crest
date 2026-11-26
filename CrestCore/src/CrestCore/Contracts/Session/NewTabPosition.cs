namespace CrestCore.Contracts;

/// Where among the open tabs a new tab the person opens goes: at the top,
/// just under New Tab, or at the bottom. The stored preferences spell a
/// position as its `Name`, so a name never changes. A position travels as its
/// index in `All`, so `All` is append-only.
public sealed class NewTabPosition {
    #region Static Variables

    public static readonly NewTabPosition Top = new(name: "top", title: "Top", insertionIndex: null);

    public static readonly NewTabPosition Bottom = new(name: "bottom", title: "Bottom", insertionIndex: int.MaxValue);

    public static IReadOnlyList<NewTabPosition> All { get; } = [Top, Bottom];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the tab settings call the position.
    [Localized]
    public string Title { get; }

    /// Where in the open tabs `BrowserTabCollection.InsertTab` puts a tab at
    /// this position: null for the top of its section, where a new tab goes,
    /// and past its end, which the section holds to its last place.
    internal int? InsertionIndex { get; }

    #endregion

    #region Constructors

    private NewTabPosition(string name, string title, int? insertionIndex) {
        Name = name;
        Title = title;
        InsertionIndex = insertionIndex;
    }

    #endregion

    #region Actions - Lookup

    public static NewTabPosition? Named(string? name) => All.FirstOrDefault(position => position.Name == name);

    #endregion
}
