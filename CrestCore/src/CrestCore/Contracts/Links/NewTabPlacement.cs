using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Where a tab the person opens goes among the open tabs of its section:
/// after the tab they came from, at the top, or at the bottom. A tab never
/// lands above the pinned or saved tabs, which are other sections, or inside
/// a split.
///
/// Link preferences (`crest.link-preferences.v1`) and the device store spell a
/// placement as its `Name`, so a name never changes. A placement travels as
/// its index in `All`, so `All` is append-only.
public sealed class NewTabPlacement {
    #region Static Variables

    /// Directly after the tab the person came from, or after its whole split.
    public static readonly NewTabPlacement AfterCurrent = new(name: "afterCurrent", title: "After current tab",
        index: (tabs, current) => current is { } origin ? tabs.InsertionIndexAfter(origin) : null);

    /// At the top of the section, which its tab count clamps the index into.
    public static readonly NewTabPlacement Top = new(name: "top", title: "At the top", index: (_, _) => 0);

    /// At the bottom of the section, which its tab count clamps the index into.
    public static readonly NewTabPlacement Bottom = new(name: "bottom", title: "At the bottom", index: (_, _) => int.MaxValue);

    public static IReadOnlyList<NewTabPlacement> All { get; } = [AfterCurrent, Top, Bottom];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the tab settings call the placement.
    [Localized]
    public string Title { get; }

    private readonly Func<BrowserTabCollection, Guid?, int?> index;

    #endregion

    #region Constructors

    private NewTabPlacement(string name, string title, Func<BrowserTabCollection, Guid?, int?> index) {
        Name = name;
        Title = title;
        this.index = index;
    }

    #endregion

    #region Actions - Lookup

    public static NewTabPlacement? Named(string? name) => All.FirstOrDefault(placement => placement.Name == name);

    #endregion

    #region Actions - Placement

    /// The index `tabs.InsertTab` takes for a tab opened from `current`, or
    /// null to leave it to the tab's section.
    internal int? InsertionIndex(BrowserTabCollection tabs, Guid? current) {
        ArgumentNullException.ThrowIfNull(tabs);
        return index(tabs, current);
    }

    #endregion
}
