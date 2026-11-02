using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Puts the workspace's Spaces in the order `SpaceIds` lists, which names
/// each of them once. A group stays together where its primary goes, its
/// Sub-Spaces in the order the list gives them, so moving a primary moves its
/// group and a Sub-Space moves only within its group.
public sealed record ReorderSpaces(Guid WorkspaceId, IReadOnlyList<Guid> SpaceIds) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var byId = turn.Basis.Spaces.ToDictionary(space => space.Id);
        if (SpaceIds.Count != byId.Count || SpaceIds.Distinct().Count() != byId.Count || SpaceIds.Any(id => !byId.ContainsKey(id)))
            throw new Rejected(new InvalidSpaceOrder());
        var pending = turn.Basis.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        var spaces = SpaceGroup.Regrouped([.. SpaceIds.Select(id => byId[id])], pending);
        return new(turn.Basis.Spaces.SequenceEqual(spaces) ? turn.Basis : turn.Basis with { Spaces = spaces }, SyncStaging.Edit);
    }

    #endregion
}
