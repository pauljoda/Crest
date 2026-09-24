namespace CrestCore.Contracts;

/// A name is longer than `Limit` characters, or blank where one is required.
public sealed record InvalidName(int Limit) : Rejection;
