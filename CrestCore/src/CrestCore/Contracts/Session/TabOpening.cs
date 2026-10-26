using CrestCore.Application;

namespace CrestCore.Contracts;

/// Why a tab opens, which decides where it goes. A tab the person opens as a
/// new tab or from a link goes where their link preferences say; a tab that
/// software opens ignores both and follows the last tab its opener opened.
///
/// An opening travels as its index in `All`, so `All` is append-only.
public sealed class TabOpening {
    #region Static Variables

    /// A Start Page, an address typed in the command bar, a link another app
    /// handed Crest, or a kept Quick Window.
    public static readonly TabOpening NewTab = new(name: "newTab", placement: links => links.NewTabPlacement, clusters: false);

    /// A followed link, or a kept Peek.
    public static readonly TabOpening Link = new(name: "link", placement: links => links.LinkedTabPlacement, clusters: false);

    /// An agent, the sidebar or any other caller that is not the person's own
    /// gesture. Its tabs cluster: each goes after the last tab the same
    /// opener opened, starting after the current tab.
    public static readonly TabOpening Programmatic = new(name: "programmatic", placement: _ => NewTabPlacement.AfterCurrent,
        clusters: true);

    public static IReadOnlyList<TabOpening> All { get; } = [NewTab, Link, Programmatic];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether a tab goes after the last tab its opener opened.
    public bool Clusters { get; }

    private readonly Func<LinkPreferences, NewTabPlacement> placement;

    #endregion

    #region Constructors

    private TabOpening(string name, Func<LinkPreferences, NewTabPlacement> placement, bool clusters) {
        Name = name;
        Clusters = clusters;
        this.placement = placement;
    }

    #endregion

    #region Actions - Lookup

    public static TabOpening? Named(string? name) => All.FirstOrDefault(opening => opening.Name == name);

    #endregion

    #region Actions - Placement

    /// The tab a new tab opens after: for an opening that clusters, the last
    /// tab `opener` opened that is still in `placement`'s section of `space`,
    /// else `current`, the tab it opens from. The caller holds the gate.
    internal Guid? Origin(NativeSessionAuthority workspace, Guid? opener, SpaceState space, TabPlacement placement, Guid? current) =>
        Clusters ? workspace.LastOpenedBy(opener, space, placement) ?? current : current;

    /// The tab to remember as `opener`'s last, or null for an opening that does
    /// not cluster or an opener that is unnamed.
    internal OpenedTab? Opened(Guid? opener, Guid tab) => Clusters && opener is { } id ? new OpenedTab(id, tab) : null;

    /// Where a tab opened this way goes under `links`.
    internal NewTabPlacement PlacementUnder(LinkPreferences links) {
        ArgumentNullException.ThrowIfNull(links);
        return placement(links);
    }

    #endregion
}
