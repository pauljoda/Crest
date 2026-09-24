namespace CrestCore.Contracts;

/// Only a private workspace starts over.
public sealed record NotPrivateWorkspace(Guid WorkspaceId) : Rejection;
