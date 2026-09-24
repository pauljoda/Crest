namespace CrestCore.Contracts;

/// The Space already holds `Limit` tabs, so it takes no more.
public sealed record TabLimitReached(int Limit) : Rejection;
