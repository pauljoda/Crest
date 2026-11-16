using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a page of `SpaceId` showing `Origin` blocks ads and trackers: the
/// device blocks at a level that blocks, and blocking is not off for the site.
/// Without an origin, such as for a blank page, only the level counts.
public sealed record ContentBlockingApplies(Guid SpaceId, SiteOrigin? Origin) : Query<bool> {
    #region Actions - Answering

    internal override bool Answer(CrestApp app) => app.Device.Blocks(SpaceId, Origin);

    #endregion
}
