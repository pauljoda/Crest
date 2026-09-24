namespace CrestCore.Contracts;

/// Only the persistent workspace keeps the app-wide preferences.
public sealed record PersistentWorkspaceRequired(Guid WorkspaceId) : Rejection;
