using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets when a Space cleans up open tabs, how it blocks content and how long
/// it keeps what it browses; the last two are its group's, so every Space of
/// the group takes them. A Space whose cleanup or retention changed is swept
/// under the new rules in the same edit. What it searches with and whether it
/// suggests searches is `SetSpaceSearch`'s.
public sealed record SetBrowsingPreferences(Guid WorkspaceId, Guid SpaceId, CurrentTabCleanup CurrentTabCleanup,
    ContentBlockingPolicy ContentBlocking, DataRetentionPreferences DataRetention)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Sets the Space's browsing preferences apart from its search. A
    /// changed cleanup or retention sweeps the Space under the new rules in
    /// the same edit, which then stages as the records it expired.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var before = space.Settings.BrowsingPreferences;
        var preferences = before with {
            CurrentTabCleanup = CurrentTabCleanup,
            ContentBlocking = ContentBlocking,
            DataRetention = DataRetention
        };
        var protects = before.ContentBlocking != ContentBlocking || before.DataRetention != DataRetention;
        var configured = space.Configured(space.Settings with {
            BrowsingPreferences = preferences,
            ProtectionModifiedAt = protects
                ? SpaceSettings.Chosen(space.Settings.ProtectionModifiedAt, turn.Now) : space.Settings.ProtectionModifiedAt
        });
        var shared = protects ? turn.Basis.Sharing(configured, GroupSetting.Protection) : turn.Basis.Replacing(configured);
        if (before.CurrentTabCleanup == preferences.CurrentTabCleanup && before.DataRetention == preferences.DataRetention)
            return new(shared, SyncStaging.Edit);
        // The Space sweeps its tabs under its cleanup, and every Space of its
        // group its records under the retention they now share.
        var kept = workspace.TabsCleanupKeeps(turn);
        var swept = shared.Replacing(configured.CleanedUp(turn.Now, kept));
        var members = swept.GroupOf(space.Id)?.Members ?? [swept.KnownSpace(space.Id)];
        var retained = swept.Replacing([.. members.Where(member => swept.PendingDeletion(member.Id) is null)
            .Select(member => member.Retained(turn.Now))]);
        return new(retained, members.All(member => workspace.SameRecords(shared.KnownSpace(member.Id), retained.KnownSpace(member.Id)))
            ? SyncStaging.Edit : SyncStaging.Expiry);
    }

    #endregion
}
