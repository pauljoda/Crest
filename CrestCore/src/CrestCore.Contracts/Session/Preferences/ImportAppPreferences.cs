namespace CrestCore.Contracts;

/// Gives the persistent workspace the preferences the settings kept before the
/// core owned them, once: a workspace that already holds preferences keeps
/// them, so a later launch never imports over a choice.
public sealed record ImportAppPreferences(Guid WorkspaceId, LegacyAppPreferences Legacy) : SessionIntent(WorkspaceId);
