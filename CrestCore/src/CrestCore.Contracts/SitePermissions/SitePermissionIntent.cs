namespace CrestCore.Contracts;

/// An intent about this device's site permission choices. The device store
/// keeps the persistent session's choices beside the session, never in it,
/// and they never sync; every other Space's choices live in memory until the
/// process ends.
public abstract record SitePermissionIntent : Intent;
