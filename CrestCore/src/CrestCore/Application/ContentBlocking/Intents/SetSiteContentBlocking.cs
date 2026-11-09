using CrestCore.Application;

namespace CrestCore.Contracts;

/// Blocks, or stops blocking, ads and trackers on `Origin` in every Space, as
/// a page of `SpaceId` asked. Turning it off from a Space of the persistent
/// session is kept by the device store; from any other Space, such as a
/// private one, it lives as long as the process. Refused for an origin that is
/// not valid, or for turning it off from a locked Space.
public sealed record SetSiteContentBlocking(Guid SpaceId, SiteOrigin Origin, bool Blocks) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.SetBlocking(SpaceId, Origin, Blocks, changes));

    #endregion
}
