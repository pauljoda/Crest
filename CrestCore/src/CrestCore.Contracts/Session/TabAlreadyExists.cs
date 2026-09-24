namespace CrestCore.Contracts;

/// The workspace already holds an open tab with this identity.
public sealed record TabAlreadyExists(Guid TabId) : Rejection;
