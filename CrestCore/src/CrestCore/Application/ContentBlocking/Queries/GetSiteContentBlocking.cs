using CrestCore.Application;

namespace CrestCore.Contracts;

/// Every site where Crest blocks no ads or trackers.
public sealed record GetSiteContentBlocking : Query<IReadOnlyList<SiteContentBlocking>> {
    #region Actions - Answering

    internal override IReadOnlyList<SiteContentBlocking> Answer(CrestApp app) => app.Device.BlockingSites;

    #endregion
}
