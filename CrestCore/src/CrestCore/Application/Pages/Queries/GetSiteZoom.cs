using CrestCore.Application;

namespace CrestCore.Contracts;

/// The zoom saved for the HTTP(S) host of `Url` in the page's profile. A page
/// in a locked, deleted or missing Space cannot read its preferences.
public sealed record GetSiteZoom(Guid PageId, string Url) : Query<SiteZoomPreference> {
    #region Actions - Answering

    internal override SiteZoomPreference Answer(CrestApp app) => app.Device.SiteZoom(app.Pages.Known(PageId), Url);

    #endregion
}
