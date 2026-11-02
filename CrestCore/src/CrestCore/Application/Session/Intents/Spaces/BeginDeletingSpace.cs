using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Starts deleting a Space as the deletion `OperationId` names, and saves
/// that before it returns. The Space and its profile stay exactly as they are
/// until `FinishDeletingSpace` removes them, which the platform sends once it
/// has erased the profile's data. Beginning again with the same operation, as
/// a relaunch does, changes nothing. The window that asked moves to the first
/// Space that stays, when it showed this one. A locked Space may be deleted,
/// except a primary that leads Sub-Spaces: it hands its group to
/// `NewPrimaryId`, one of them, or to the first when none is named, with the
/// group's records, which takes the group unlocked.
public sealed record BeginDeletingSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid OperationId, Guid? NewPrimaryId = null)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Records the deletion, which leaves the Space as it is until it is
    /// removed. The window showing a Space that is going away moves to the
    /// first one that stays.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var (space, pending) = workspace.Deleting(turn.Basis, SpaceId);
        if (pending is not null)
            return pending.Id == OperationId
                ? new(turn.Basis, SyncStaging.Withdrawal)
                : throw new Rejected(new WrongDeletionOperation(space.Id));
        SessionState.RequireRemovable(turn.Basis.Spaces.Count - turn.Basis.SpaceDeletions.Count);
        var basis = turn.Basis;
        Guid? successor = null;
        if (basis.Leads(space.Id)) {
            workspace.Editable(basis, space.Id);
            var group = basis.GroupOf(space.Id)!;
            var chosen = NewPrimaryId is { } named
                ? group.SubSpaces.FirstOrDefault(member => member.Id == named) ?? throw new Rejected(new InvalidNewPrimary(named))
                : group.SubSpaces[0];
            basis = basis.HandingOver(group, chosen, turn.Now);
            space = basis.KnownSpace(space.Id);
            successor = chosen.Id;
        }
        var next = basis with {
            SpaceDeletions = [.. basis.SpaceDeletions, basis.Deleting(space, OperationId) with { SuccessorId = successor }]
        };
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (followUp.Window?.ShownSpaceId == space.Id)
            followUp.ShowSpace(successor ?? next.Spaces.First(candidate => next.PendingDeletion(candidate.Id) is null).Id);
        return new(next, SyncStaging.Withdrawal, followUp);
    }

    #endregion

    #region Actions - Routing

    /// The Sub-Space that takes over a deleted primary's group keeps the
    /// site choices the primary kept for it.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        base.Commit(app, changes);
        if (app.Device.Workspace(WorkspaceId).Current.PendingDeletion(SpaceId)?.SuccessorId is { } successor)
            app.Device.HandOverSitePermissions(SpaceId, successor, changes);
    }

    #endregion
}
