namespace CrestCore.Contracts;

/// Neither workspace borrows the other's Spaces, and they borrow from no
/// workspace in common, so no tab moves between them.
public sealed record UnrelatedWorkspaces(Guid DestinationWorkspaceId) : Rejection;
