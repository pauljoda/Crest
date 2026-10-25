using CrestCore.Application;

namespace CrestCore.Contracts;

/// Chooses Developer Mode on or off for the site the page `PageId` names
/// shows, or forgets the choice when `IsOn` is null so the site follows the
/// default again. A choice made in a Space of the persistent session holds for
/// every Space, and the device store keeps it; past its limit, the least
/// recently chosen site is forgotten. One made in any other Space, such as a
/// private one, holds for that Space alone and lives as long as the process.
/// Every open page of the site carries the choice at once. Refused when the
/// page is not open, shows no web page's address, or its Space is locked.
public sealed record ChooseSiteDeveloperMode(Guid PageId, bool? IsOn) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        var origin = page.Origin ?? throw new Rejected(new PageShowsNoSite(PageId));
        if (!pages.Device.ChooseDeveloperMode(page.SpaceId, origin, IsOn)) return;
        foreach (var shown in pages.All.Where(other => other.Origin == origin))
            turn.Changes.Publish(new PageChanged(shown.State));
    }

    #endregion
}
