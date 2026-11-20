using CrestCore.Application;

namespace CrestCore.Contracts;

/// Puts the workspace's Spaces in the order `SpaceIds` lists, which names
/// each of them once. A Space keeps its group and profile in any position.
public sealed record ReorderSpaces(Guid WorkspaceId, IReadOnlyList<Guid> SpaceIds) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var byId = turn.Basis.Spaces.ToDictionary(space => space.Id);
        if (SpaceIds.Count != byId.Count || SpaceIds.Distinct().Count() != byId.Count || SpaceIds.Any(id => !byId.ContainsKey(id)))
            throw new Rejected(new InvalidSpaceOrder());
        var spaces = SpaceIds.Select(id => byId[id]).ToArray();
        return new(turn.Basis.Spaces.SequenceEqual(spaces) ? turn.Basis : turn.Basis with { Spaces = spaces }, SyncStaging.SpaceOrder);
    }

    #endregion
}
