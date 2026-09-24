namespace CrestCore.Contracts;

/// The Space already holds `Limit` custom search engines.
public sealed record SearchEngineLimitReached(int Limit) : Rejection;
