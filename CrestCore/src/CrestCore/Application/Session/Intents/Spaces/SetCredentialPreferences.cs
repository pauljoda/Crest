using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets whether a Space, and every Space of its group, offers to save and fill
/// passwords, which reaches the person's other devices, and where it keeps
/// them, which stays on this one.
public sealed record SetCredentialPreferences(Guid WorkspaceId, Guid SpaceId, CredentialPreferences Preferences)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = space.Configured(space.Settings with {
            CredentialPreferences = Preferences,
            CredentialsEnabledModifiedAt = Preferences.IsEnabled == space.Settings.CredentialPreferences.IsEnabled
                ? space.Settings.CredentialsEnabledModifiedAt
                : SpaceSettings.Chosen(space.Settings.CredentialsEnabledModifiedAt, turn.Now)
        });
        return new(turn.Basis.Sharing(edited, GroupSetting.CrestPasswords), SyncStaging.Protection);
    }

    #endregion
}
