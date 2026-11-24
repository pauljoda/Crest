using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets whether a Space, and every Space of its group, offers to save and fill
/// passwords, which reaches the person's other devices, and where it keeps
/// them and which sites it never offers to save for, which stay on this one.
/// The sites are kept once each, valid ones only, up to the most a Space keeps.
public sealed record SetCredentialPreferences(Guid WorkspaceId, Guid SpaceId, CredentialPreferences Preferences)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var preferences = Preferences with {
            NeverSavedSites = [.. Preferences.NeverSavedSites.Where(site => site.IsValid).Distinct()
                .Take(CredentialPreferences.MaximumNeverSavedSites)]
        };
        var edited = space.Configured(space.Settings with {
            CredentialPreferences = preferences,
            CredentialsEnabledModifiedAt = preferences.IsEnabled == space.Settings.CredentialPreferences.IsEnabled
                ? space.Settings.CredentialsEnabledModifiedAt
                : SpaceSettings.Chosen(space.Settings.CredentialsEnabledModifiedAt, turn.Now)
        });
        return new(turn.Basis.Sharing(edited, GroupSetting.CrestPasswords), SyncStaging.Protection);
    }

    #endregion
}
