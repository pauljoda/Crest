using CrestCore.Application;

namespace CrestCore.Contracts;

/// Saves the page's zoom for `Url`'s HTTP(S) hostname in its browsing profile.
/// Null removes the override. Private profiles keep it only until their
/// workspace closes; persistent profiles save it locally across launches.
public sealed record SetSiteZoom(Guid PageId, string Url, double? Factor) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) =>
        pages.Device.SetSiteZoom(pages.Known(PageId), Url, Factor, turn.Changes);

    #endregion
}
