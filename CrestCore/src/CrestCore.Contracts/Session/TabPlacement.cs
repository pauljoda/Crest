namespace CrestCore.Contracts;

/// Where a tab lives in its Space. `All` lists the sections in the order a
/// Space shows them: pinned, saved, then open.
///
/// The stored session and the synced tab and folder records spell a placement
/// as its `Name`, so a name never changes. A placement travels as its index in
/// `All`, so `All` is append-only.
public sealed class TabPlacement {
    #region Variables

    /// The most pinned tabs one Space holds.
    public const int PinnedCapacity = 12;

    public static readonly TabPlacement Pinned = new(name: "pinned", title: "Pinned", symbol: "pin.fill", rank: 0, fallbackRank: 1,
        isDurable: true, holdsFolders: false, holdsSplits: false, isCollapsible: false, capacity: PinnedCapacity);
    public static readonly TabPlacement Saved = new(name: "saved", title: "Saved", symbol: "bookmark.fill", rank: 1, fallbackRank: 2,
        isDurable: true, holdsFolders: true, holdsSplits: true, isCollapsible: true, capacity: null);
    public static readonly TabPlacement Current = new(name: "current", title: "Open", symbol: "rectangle.stack.fill", rank: 2,
        fallbackRank: 0, isDurable: false, holdsFolders: true, holdsSplits: true, isCollapsible: false, capacity: null);

    public static IReadOnlyList<TabPlacement> All { get; } = [Pinned, Saved, Current];

    public string Name { get; }

    /// What the person calls the section.
    [Localized]
    public string Title { get; }

    /// The SF Symbol that stands for the section.
    public string Symbol { get; }

    /// The section's position in a Space, first at zero. An earlier section
    /// is also the more durable one, so a conflict keeps the lower rank.
    public int Rank { get; }

    /// Which section a Space falls back to when its selection is gone, lowest
    /// first: an open tab, then a pinned one, then a saved one.
    public int FallbackRank { get; }

    /// The tab outlives the session: closing it only puts its page away, and
    /// it remembers the address it was saved at.
    public bool IsDurable { get; }

    /// The section holds folders of tabs.
    public bool HoldsFolders { get; }

    /// A tab in the section may join a split.
    public bool HoldsSplits { get; }

    /// A person may collapse the section in the sidebar, which a Space's
    /// settings remember as whether its saved tabs are expanded.
    public bool IsCollapsible { get; }

    /// The most tabs the section holds in one Space, or null for no limit
    /// beyond the Space's own.
    public int? Capacity { get; }

    #endregion

    #region Constructors

    private TabPlacement(string name, string title, string symbol, int rank, int fallbackRank, bool isDurable, bool holdsFolders,
        bool holdsSplits, bool isCollapsible, int? capacity) {
        Name = name;
        Title = title;
        Symbol = symbol;
        Rank = rank;
        FallbackRank = fallbackRank;
        IsDurable = isDurable;
        HoldsFolders = holdsFolders;
        HoldsSplits = holdsSplits;
        IsCollapsible = isCollapsible;
        Capacity = capacity;
    }

    #endregion

    #region Actions - Lookup

    public static TabPlacement? Named(string? name) => All.FirstOrDefault(placement => placement.Name == name);

    #endregion

    #region Actions - Sections

    /// The placement a tab keeps when two devices disagree: the more durable one.
    public TabPlacement Retained(TabPlacement other) {
        ArgumentNullException.ThrowIfNull(other);
        return Rank <= other.Rank ? this : other;
    }

    /// Whether the section can hold `count` tabs in one Space.
    public bool Holds(int count) => Capacity is not { } capacity || count <= capacity;

    /// The index of the tab a Space falls back to, given its tabs' placements
    /// in Space order: the first tab of the section with the lowest
    /// `FallbackRank`, or null for an empty Space.
    public static int? Fallback(IReadOnlyList<TabPlacement> placements) {
        ArgumentNullException.ThrowIfNull(placements);
        return placements.Count == 0 ? null
            : placements.Select((placement, index) => (placement.FallbackRank, index)).Min().index;
    }

    #endregion
}
