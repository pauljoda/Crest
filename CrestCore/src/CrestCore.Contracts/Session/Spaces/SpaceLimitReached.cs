namespace CrestCore.Contracts;

/// The workspace already holds `Limit` Spaces.
public sealed record SpaceLimitReached(int Limit) : Rejection;
