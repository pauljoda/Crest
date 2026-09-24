namespace CrestCore.Contracts;

/// A language identifier is longer than `Limit` characters.
public sealed record LanguageTooLong(int Limit) : Rejection;
