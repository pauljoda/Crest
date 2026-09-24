namespace CrestCore.Domain;

/// Where a link activation goes: in place, into Peek, or into a new tab. The
/// link-navigation policies spell a decision as its `Name`.
public sealed class LinkNavigationDecision {
    #region Variables

    public static readonly LinkNavigationDecision Navigate = new(name: "navigate");
    public static readonly LinkNavigationDecision PeekModifier = new(name: "peekModifier");
    public static readonly LinkNavigationDecision PeekSavedSite = new(name: "peekSavedSite");
    public static readonly LinkNavigationDecision BackgroundTab = new(name: "backgroundTab");
    public static readonly LinkNavigationDecision ForegroundTab = new(name: "foregroundTab");

    public static IReadOnlyList<LinkNavigationDecision> All { get; } =
        [Navigate, PeekModifier, PeekSavedSite, BackgroundTab, ForegroundTab];

    public string Name { get; }

    #endregion

    #region Constructors

    private LinkNavigationDecision(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static LinkNavigationDecision? Named(string? name) => All.FirstOrDefault(decision => decision.Name == name);

    #endregion
}
