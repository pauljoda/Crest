using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Asks a page to load what the person typed or chose: an address, or words
/// the Space's search engine looks up. The core resolves `Input` by the
/// address rules of the page's Space and engine, shows the page heading there
/// and asks the page's engine to load it. Refused when the page is not open or
/// its engine holds no page to load into, its Space is locked or being
/// deleted, or `Input` names nothing a page can load, as blank input does.
public sealed record Navigate(Guid PageId, string Input) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) =>
        Load(pages, turn, PageId, (preferences, showsInternalPages) => AddressResolution.Loading(Input, preferences, showsInternalPages));

    /// Loads into page `pageId` the address `resolve` makes for its Space's
    /// browsing preferences and whether its engine shows internal pages. A
    /// load to a site chosen for another registered engine moves the page
    /// there, which loads it instead.
    internal static void Load(Pages pages, PageTurn turn, Guid pageId, Func<BrowsingPreferences, bool, string> resolve) {
        var page = pages.Known(pageId);
        if (!page.Phase.HoldsEnginePage) throw new Rejected(new PageNotLoadable(page.Id));
        var space = pages.Hosting(pages.Device.Workspace(page.WorkspaceId), page.SpaceId);
        var url = resolve(space.Settings.BrowsingPreferences, page.Engine.Supports(EngineCapability.InternalPages));
        if (pages.Chosen(space, url) is { } chosen && !ReferenceEquals(chosen, page.Engine)) {
            turn.Closing.Move(page, chosen, url, RehostReason.SiteChoice, remembersSite: false, turn);
            return;
        }
        pages.Update(page, turn.Changes, () => page.Load(url));
        turn.Issue(page.Engine, new LoadPage(page.Id, url));
    }

    #endregion
}
