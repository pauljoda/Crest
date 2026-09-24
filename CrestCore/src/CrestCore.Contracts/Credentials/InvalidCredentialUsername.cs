namespace CrestCore.Contracts;

/// A username to match is empty, or a username is longer than its limit.
public sealed record InvalidCredentialUsername() : Rejection;
