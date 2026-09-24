namespace CrestCore.Contracts;

/// Replaces everything a private workspace holds with one fresh private
/// Space, which the window that asked shows.
public sealed record ResetPrivateBrowsing(Guid WorkspaceId, Guid WindowId) : SessionIntent(WorkspaceId);
