using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Removes a Space whose deletion `OperationId` began, once the platform has
/// erased the data its deletion erases, and saves that before it returns. The
/// Space that takes its place becomes the launch Space when it was one, and
/// the window that asked moves there when it showed the removed one; the
/// Sub-Spaces of a primary that goes stay together, led by the first of them.
public sealed record FinishDeletingSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid OperationId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Removes the Space and its deletion. The Space that takes its place is
    /// where its window goes and, when it was the launch Space, the new one.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var (space, pending) = workspace.Deleting(turn.Basis, SpaceId);
        if (pending is null || pending.Id != OperationId) throw new Rejected(new WrongDeletionOperation(space.Id));
        SessionState.RequireRemovable(turn.Basis.Spaces.Count);
        var index = turn.Basis.Spaces.ToList().IndexOf(space);
        var remaining = turn.Basis.SpaceDeletions.Where(deletion => deletion != pending).Select(deletion => deletion.SpaceId).ToHashSet();
        var spaces = SpaceGroup.Regrouped([.. turn.Basis.Spaces.Where(candidate => candidate.Id != space.Id)], remaining);
        var neighbor = spaces[Math.Min(index, spaces.Count - 1)].Id;
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (followUp.Window?.ShownSpaceId == space.Id) followUp.ShowSpace(neighbor);
        return new(turn.Basis with {
            Spaces = spaces,
            SpaceDeletions = [.. turn.Basis.SpaceDeletions.Where(deletion => deletion != pending)],
            DefaultSpaceId = turn.Basis.DefaultSpaceId == space.Id ? neighbor : turn.Basis.DefaultSpaceId
        }, SyncStaging.Removal, followUp);
    }

    #endregion

    #region Actions - Routing

    /// A Space's deletion finishes only once this run erased, on every
    /// registered engine, the data of each profile its deletion erases; a
    /// Space the session no longer holds is the session's to refuse. A deleted
    /// Space leaves nothing in this device's link, agent or site preferences,
    /// except the site choices a primary kept for the group it handed over,
    /// which its successor keeps.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        var deletion = app.Device.Workspace(WorkspaceId).Current.PendingDeletion(SpaceId);
        if (deletion is not null && deletion.Erasing.Any(profile => !app.DataDeletions.Erased(profile)))
            throw new Rejected(new SpaceDataNotErased(SpaceId));
        base.Commit(app, changes);
        if (deletion?.SuccessorId is { } successor) app.Device.HandOverSitePermissions(SpaceId, successor, changes);
        app.Device.ForgetSitePermissions(SpaceId, changes);
        app.Device.ForgetLinks(SpaceId, changes);
        app.Device.ForgetAgents(SpaceId, changes);
    }

    #endregion
}
