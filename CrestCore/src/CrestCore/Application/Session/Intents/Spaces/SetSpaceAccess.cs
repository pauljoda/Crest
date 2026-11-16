using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets whether a Space, and every Space of its group, opens freely or asks
/// the device owner first, which reaches the person's other devices with the
/// time they chose. Asking for authentication is allowed wherever the
/// workspace locks its Spaces, which a private one never does; letting a
/// locked Space open freely takes the grant that unlocking it gives.
public sealed record SetSpaceAccess(Guid WorkspaceId, Guid SpaceId, SpaceAccessPolicy Policy) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Asking for authentication is allowed even for a locked Space, except in
    /// a workspace that never locks one; letting a Space open freely is the
    /// decision authentication guards.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        if (Policy != SpaceAccessPolicy.Open && !workspace.Kind.LocksSpaces)
            throw new Rejected(new PrivateSpaceCannotLock(WorkspaceId));
        var space = workspace.Editable(turn.Basis, SpaceId, maintains: Policy != SpaceAccessPolicy.Open);
        var settings = space.Settings;
        var edited = space.Configured(settings with {
            AccessPolicy = Policy,
            AccessPolicyModifiedAt = Policy == settings.AccessPolicy
                ? settings.AccessPolicyModifiedAt : SpaceSettings.Chosen(settings.AccessPolicyModifiedAt, turn.Now)
        });
        return new(turn.Basis.Sharing(edited, GroupSetting.Lock), SyncStaging.Protection);
    }

    #endregion
}
