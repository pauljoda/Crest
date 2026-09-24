namespace CrestCore.Contracts;

/// The Space already holds an open tab with this identity.
public sealed record DuplicateTab(Guid TabId) : Rejection;
