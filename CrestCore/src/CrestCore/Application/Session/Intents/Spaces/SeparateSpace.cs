using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Separates a Sub-Space from its group: it moves right after the group and
/// browses with a session of its own again, the one it had before it joined
/// or a fresh one. It keeps its tabs, its own pinned tabs and what it recorded
/// before it joined, and its settings as the group had them; what it recorded
/// while in the group stays with the primary. Only a Sub-Space separates, and
/// it must be unlocked.
public sealed record SeparateSpace(Guid WorkspaceId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var basis = turn.Basis;
        var space = basis.KnownSpace(workspace.Editable(basis, SpaceId).Id);
        if (space.PrimaryId is not { } primaryId) throw new Rejected(new PrimaryCannotSeparate(space.Id));
        var separated = space with { Membership = SpaceMembership.Leaving(turn.Now) };
        var spaces = basis.Spaces.Where(candidate => candidate.Id != space.Id).ToList();
        var last = spaces.FindLastIndex(candidate => candidate.Id == primaryId || candidate.PrimaryId == primaryId);
        spaces.Insert(last + 1, separated);
        var pending = basis.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        return new(basis with { Spaces = SpaceGroup.Regrouped(spaces, pending) }, SyncStaging.Edit);
    }

    #endregion

    #region Actions - Routing

    /// The separated Space keeps the agent choice of the group it left.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        var primaryId = app.Device.Workspace(WorkspaceId).Current.Space(SpaceId)?.PrimaryId;
        base.Commit(app, changes);
        if (primaryId is { } primary) app.Device.ShareAgents(SpaceId, primary, changes);
    }

    #endregion
}
