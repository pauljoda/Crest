namespace CrestCore.Contracts;

/// The tab would cross between private browsing and other browsing, which
/// share nothing.
public sealed record PrivateWorkspaceBoundary(Guid DestinationWorkspaceId) : Rejection;
