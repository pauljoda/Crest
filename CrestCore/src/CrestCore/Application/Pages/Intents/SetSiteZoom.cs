using CrestCore.Application;

namespace CrestCore.Contracts;

/// Keeps `Factor` as the zoom of `Url`'s HTTP(S) host in the page's browsing
/// profile, so every page of the profile shows the host at it, now and after a
/// relaunch; null, or the device's default zoom, keeps none, so the host
/// follows the default. A private profile keeps it only while a window
/// browses with it. Refused for an address without an HTTP(S) host, a zoom a
/// page may not start at, and a page whose Space is locked or being deleted.
public sealed record SetSiteZoom(Guid PageId, string Url, double? Factor) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        pages.Device.KeepSiteZoom(page, pages.Browsing(page), Url, Factor, turn.Changes);
    }

    #endregion
}
