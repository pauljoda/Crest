using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Makes a Space a Sub-Space of the group `GroupSpaceId` belongs to, at the
/// end of that group; a Space on its own becomes the primary of the group it
/// starts. The joining Space browses with the group's session from then on,
/// keeps its tabs, its pinned tabs (hidden while the group shares the
/// primary's) and what it recorded before, and takes the group's shared
/// settings, except that the group locks when either side was locked:
/// protection never drops on a join. A Sub-Space of another group leaves that
/// one first. Both Spaces must be unlocked, a private window's Space never
/// shares, and a primary joins no other group.
public sealed record JoinSpace(Guid WorkspaceId, Guid SpaceId, Guid GroupSpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        if (workspace.Kind.IsPrivate) throw new Rejected(new PrivateSpaceCannotShare(WorkspaceId));
        var basis = turn.Basis;
        var joining = basis.KnownSpace(workspace.Editable(basis, SpaceId).Id);
        var target = basis.KnownSpace(workspace.Editable(basis, GroupSpaceId).Id);
        var primary = basis.GroupOf(target.Id)?.Primary ?? target;
        if (primary.Id == joining.Id || joining.PrimaryId == primary.Id) return new(basis, SyncStaging.Edit);
        if (basis.Leads(joining.Id) || joining.ProfileId != joining.OwnProfileId && joining.PrimaryId is null)
            throw new Rejected(new PrimaryCannotJoin(joining.Id));
        // The joining Space's lock, when only it had one, becomes the group's newest choice.
        var lockChoice = joining.Settings.RequiresAuthentication && !primary.Settings.RequiresAuthentication
            ? joining.Settings with { AccessPolicyModifiedAt = SpaceSettings.Chosen(primary.Settings.AccessPolicyModifiedAt, turn.Now) }
            : primary.Settings;
        var settings = GroupSetting.All.Aggregate(joining.Settings,
            (value, setting) => setting.Copied(setting == GroupSetting.Lock ? lockChoice : primary.Settings, value));
        var joined = joining.Configured(settings) with { Membership = SpaceMembership.Joining(primary, turn.Now) };
        var spaces = basis.Spaces.Where(space => space.Id != joined.Id).ToList();
        var last = spaces.FindLastIndex(space => space.Id == primary.Id || space.PrimaryId == primary.Id);
        spaces.Insert(last + 1, joined);
        var next = (basis with { Spaces = spaces }).Sharing(joined, GroupSetting.Lock);
        var pending = basis.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        return new(next with { Spaces = SpaceGroup.Regrouped(next.Spaces, pending) }, SyncStaging.Protection);
    }

    #endregion

    #region Actions - Routing

    /// The group stays open on this device where either side was: the
    /// joining Space takes the grant this process holds for the group's
    /// primary, and a group that locks because the joining Space was locked
    /// takes the joining Space's grant. Agents reach the joining Space only
    /// while they reach the group, and where the group already chose for a
    /// site, its choice stands.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        base.Commit(app, changes);
        var session = app.Device.Workspace(WorkspaceId).Current;
        if (session.Space(SpaceId) is not { PrimaryId: { } primaryId } joined || session.GroupOf(primaryId) is not { } group) return;
        SpaceAccessAssignment primary = new(group.Primary.Id, group.Primary.OwnProfileId), joining = new(joined.Id, joined.OwnProfileId);
        app.Access.Changing(changes, authority => [.. authority.Extend(primary, joining),
            .. group.Members.SelectMany(member => authority.Extend(joining, new(member.Id, member.OwnProfileId)))]);
        app.Device.ShareAgents(joined.Id, group.Primary.Id, changes);
        app.Device.ShareSitePermissions(joined.Id, changes);
    }

    #endregion
}
