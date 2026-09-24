namespace CrestCore.Contracts;

/// The split already holds `Limit` tabs.
public sealed record SplitLimitReached(int Limit) : Rejection;
