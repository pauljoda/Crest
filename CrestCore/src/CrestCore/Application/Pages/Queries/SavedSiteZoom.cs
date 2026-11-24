using CrestCore.Application;

namespace CrestCore.Contracts;

/// The zoom `Url`'s HTTP(S) host keeps in the page's browsing profile.
/// Refused for a page the core does not host, or whose Space is locked or
/// being deleted.
public sealed record SavedSiteZoom(Guid PageId, string Url) : Query<SiteZoomPreference> {
    #region Actions - Answering

    internal override SiteZoomPreference Answer(CrestApp app) {
        var page = app.Pages.Known(PageId);
        return app.Device.SiteZoom(page, app.Pages.Browsing(page), Url);
    }

    #endregion
}
