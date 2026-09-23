namespace CrestCore.Contracts;

/// A download retention lifetime is negative.
public sealed record InvalidRetentionLifetime() : Rejection;
