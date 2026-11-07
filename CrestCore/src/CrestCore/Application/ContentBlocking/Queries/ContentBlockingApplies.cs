using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a page of `SpaceId` showing `Origin` blocks ads and trackers: its
/// Space's policy blocks, and the Space did not turn blocking off for the site.
/// Without an origin, such as for a blank page, only the policy counts.
public sealed record ContentBlockingApplies(Guid SpaceId, SiteOrigin? Origin) : Query<bool> {
    #region Actions - Answering

    internal override bool Answer(CrestApp app) => app.Device.Blocks(SpaceId, Origin);

    #endregion
}
