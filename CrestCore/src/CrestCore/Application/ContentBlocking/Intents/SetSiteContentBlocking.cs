using CrestCore.Application;

namespace CrestCore.Contracts;

/// Blocks, or stops blocking, ads and trackers on `Origin` in `SpaceId`. A
/// choice made in a Space of the persistent session is kept by the device
/// store; one made in any other Space, such as a private one, lives as long as
/// the process. Refused for an origin that is not valid or a locked Space.
public sealed record SetSiteContentBlocking(Guid SpaceId, SiteOrigin Origin, bool Blocks) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.SetBlocking(SpaceId, Origin, Blocks, changes));

    #endregion
}
