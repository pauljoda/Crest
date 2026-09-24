namespace CrestCore.Contracts;

/// Only a window over the persistent session may be saved; this workspace
/// lives in memory.
public sealed record UnsavedWorkspace(Guid WorkspaceId) : Rejection;
