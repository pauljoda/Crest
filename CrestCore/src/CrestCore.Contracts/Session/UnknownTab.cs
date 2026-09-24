namespace CrestCore.Contracts;

/// The Space holds no tab with this identity.
public sealed record UnknownTab(Guid TabId) : Rejection;
