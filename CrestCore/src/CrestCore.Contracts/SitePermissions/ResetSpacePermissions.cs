namespace CrestCore.Contracts;

/// Forgets every saved and session choice in one Space, locked, deleted or
/// private alike, so resetting or deleting a Space is never blocked.
public sealed record ResetSpacePermissions(Guid SpaceId) : SitePermissionIntent;
