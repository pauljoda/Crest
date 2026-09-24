namespace CrestCore.Application;

/// A Quick Window's or Peek's page as a session intent about it reads it: the
/// workspace and Space it lives in, the profile its engine page keeps, and
/// whether its engine can move it to another window, so a tab can take it.
internal sealed record TransientPage(Guid Id, Guid WorkspaceId, Guid SpaceId, Guid ProfileId, bool MovesBetweenWindows);
