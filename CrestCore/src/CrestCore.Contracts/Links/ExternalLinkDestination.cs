namespace CrestCore.Contracts;

/// Where a link opened from outside Crest goes when no route claims it: the
/// Space it opens in, and whether it opens as a Quick Window there.
///
/// Link preferences (`crest.link-preferences.v1`) spell a destination as its
/// `Name`, so a name never changes. A destination travels as its index in
/// `All`, so `All` is append-only.
public sealed class ExternalLinkDestination {
    #region Variables

    /// A Quick Window on the Space remembered for the link's site, when the
    /// preferences remember one and it can open.
    public static readonly ExternalLinkDestination QuickWindow = new(name: "quickWindow", title: "Quick Window",
        opensQuickWindow: true, space: (preferences, context) =>
            preferences.RemembersSpaceBySite && preferences.RememberedSpaceId is { } remembered && context.IsAvailable(remembered)
                ? remembered : context.Fallback());

    public static readonly ExternalLinkDestination MostRecentSpace = new(name: "mostRecentSpace", title: "Most Recent Space",
        opensQuickWindow: false, space: (_, context) => context.Fallback());

    /// The Space the person chose, when it can open.
    public static readonly ExternalLinkDestination ChosenSpace = new(name: "chosenSpace", title: "Chosen Space",
        opensQuickWindow: false, asksForSpace: true, space: (preferences, context) =>
            preferences.ChosenSpaceId is { } chosen && context.IsAvailable(chosen) ? chosen : context.Fallback());

    public static IReadOnlyList<ExternalLinkDestination> All { get; } = [QuickWindow, MostRecentSpace, ChosenSpace];

    public string Name { get; }

    /// What the link settings call the destination.
    [Localized]
    public string Title { get; }

    public bool OpensQuickWindow { get; }

    /// The link settings ask which Space the destination opens.
    public bool AsksForSpace { get; }

    private readonly Func<LinkRoutingPreferences, LinkRoutingContext, Guid> space;

    #endregion

    #region Constructors

    private ExternalLinkDestination(string name, string title, bool opensQuickWindow,
        Func<LinkRoutingPreferences, LinkRoutingContext, Guid> space, bool asksForSpace = false) {
        Name = name;
        Title = title;
        OpensQuickWindow = opensQuickWindow;
        AsksForSpace = asksForSpace;
        this.space = space;
    }

    #endregion

    #region Actions - Lookup

    public static ExternalLinkDestination? Named(string? name) => All.FirstOrDefault(destination => destination.Name == name);

    #endregion

    #region Actions - Routing

    /// The Space a link with no matching route opens in. The selected Space,
    /// or the first that can open, stands in for one that cannot.
    public Guid Space(LinkRoutingPreferences preferences, LinkRoutingContext context) {
        ArgumentNullException.ThrowIfNull(preferences);
        ArgumentNullException.ThrowIfNull(context);
        return space(preferences, context);
    }

    #endregion
}
