using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Adds a Sub-Space right after `FromSpaceId`, joining the session of that
/// Space's group, whose primary it becomes when it is on its own. The new Space
/// wears the next number of the Space's name and copies its look and settings;
/// while the group shows separate pinned tabs it also gets copies of the
/// Space's pinned tabs. It starts with one Start Page tab and a profile of its
/// own that it never browses with while it is a Sub-Space. It opens with the
/// group when this process unlocked the group, and the window that asked shows
/// it.
public sealed record AddSubSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid FromSpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        if (workspace.Kind.IsPrivate) throw new Rejected(new PrivateSpaceCannotShare(WorkspaceId));
        var basis = turn.Basis;
        if (basis.Space(SpaceId) is not null) throw new Rejected(new SpaceAlreadyExists(SpaceId));
        if (basis.Spaces.Count >= SessionState.MaximumSpaces) throw new Rejected(new SpaceLimitReached(SessionState.MaximumSpaces));
        var from = basis.KnownSpace(workspace.Editable(basis, FromSpaceId).Id);
        var primary = basis.GroupOf(from.Id)?.Primary ?? from;
        var made = SpaceTemplate.For(privateBrowsing: false).Make(SpaceId, turn.Ids.Next(), turn.Ids.Next, basis.Spaces.Count + 1, turn.Now);
        IReadOnlyList<TabState> pins = from.Settings.SeparatesPinnedTabs
            ? [.. from.Tabs.Where(tab => tab.IsPinned).Select(tab => Copy(tab, turn.Ids.Next(), turn.Now))] : [];
        var space = made with {
            Settings = from.Settings with { Name = basis.NextName(from.Settings.Name) },
            Tabs = [.. pins, .. made.Tabs],
            Membership = SpaceMembership.Joining(primary, turn.Now)
        };
        var spaces = basis.Spaces.ToList();
        spaces.Insert(spaces.IndexOf(from) + 1, space);
        var pending = basis.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId)).ShowSpace(space.Id).ShowTab(space.Id, made.Tabs[0].Id);
        return new(basis with { Spaces = SpaceGroup.Regrouped(spaces, pending) }, SyncStaging.Creation, followUp);
    }

    /// A copy of the pinned tab `tab` named `id`, at the address it belongs to.
    private static TabState Copy(TabState tab, Guid id, DateTimeOffset now) => tab with {
        Id = id,
        Url = tab.SavedAddress ?? tab.Url,
        LastActivatedAt = now,
        PositionModifiedAt = null,
        KeepsPageLoaded = false
    };

    #endregion

    #region Actions - Routing

    /// The new Space opens with its group while this process holds the
    /// grant for the Space it was made from, and agents reach it while they
    /// reach the group.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        base.Commit(app, changes);
        var session = app.Device.Workspace(WorkspaceId).Current;
        if (session.Space(SpaceId) is not { PrimaryId: { } primaryId } added || session.Space(FromSpaceId) is not { } from) return;
        app.Access.Changing(changes, authority => authority.Extend(new(from.Id, from.OwnProfileId), new(added.Id, added.OwnProfileId)));
        app.Device.ShareAgents(added.Id, primaryId, changes);
    }

    #endregion
}
