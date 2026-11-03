using CrestCore.Application;

namespace CrestCore.Contracts;

/// The Spaces a copy of the extension `ExtensionId` the engine of `Engine`
/// installed in Space `SpaceId` may go to: one for each other profile, a
/// group's primary standing for the group, each within reach and without the
/// extension already.
public sealed record ExtensionCopyDestinations(Guid SpaceId, EngineKind Engine, string ExtensionId)
    : Query<ExtensionCopyDestinationList> {
    #region Actions - Answering

    /// Refused as `Extensions.Reachable` refuses the Space.
    internal override ExtensionCopyDestinationList Answer(CrestApp app) {
        var (space, engine) = app.Extensions.Reachable(SpaceId, Engine);
        return app.Extensions.Destinations(space, engine, ExtensionId);
    }

    #endregion
}
