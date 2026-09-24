namespace CrestCore.Contracts;

/// An intent about the browsing data one workspace's session holds: its
/// Spaces' history, archive, tabs, folders and splits. The core stamps the
/// edit with its own clock, and the session publishes what the edit changed.
/// An intent that changes nothing publishes nothing.
public abstract record SessionIntent(Guid WorkspaceId) : Intent;
