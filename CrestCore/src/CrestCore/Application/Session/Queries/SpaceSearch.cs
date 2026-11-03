using CrestCore.Application;

namespace CrestCore.Contracts;

/// What `SpaceId` in `WorkspaceId` searches with and whether it suggests
/// searches as a person types, as its address bar does: the device's default
/// while it follows it, else its own choice, or the default when that choice
/// names nothing this device keeps or the Space still carries.
public sealed record SpaceSearch(Guid WorkspaceId, Guid SpaceId) : Query<SpaceSearchAnswer> {
    #region Actions - Answering

    internal override SpaceSearchAnswer Answer(CrestApp app) {
        var workspace = app.Device.Workspace(WorkspaceId);
        return new(workspace.Searches(SpaceId), workspace.SuggestsSearches(SpaceId));
    }

    #endregion
}
