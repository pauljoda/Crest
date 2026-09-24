namespace CrestCore.Contracts;

/// Showing a tab recorded when it was last used, as the workspace's revision
/// `Revision`.
///
/// TRANSITIONAL: it keeps the platform's own copy of the session, and the
/// revision its session commands name, in step with that edit. It goes when
/// the Swift session copy retires and the platform reads the session from the
/// core's published model.
public sealed record TabActivated(Guid WorkspaceId, Guid SpaceId, Guid TabId, DateTimeOffset At, long Revision) : Change;
