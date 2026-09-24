namespace CrestCore.Contracts;

/// Sets whether a Space offers to save and fill passwords, and where it keeps them.
public sealed record SetCredentialPreferences(Guid WorkspaceId, Guid SpaceId, CredentialPreferences Preferences)
    : SessionIntent(WorkspaceId);
