namespace CrestCore.Contracts;

/// The workspace borrows its one Space from the workspace that owns the
/// Space's profile, which changes the Space's settings and makes, orders and
/// deletes Spaces.
public sealed record BorrowedProfileRequiresOwner(Guid WorkspaceId) : Rejection;
