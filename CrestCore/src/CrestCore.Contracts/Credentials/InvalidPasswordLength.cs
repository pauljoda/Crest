namespace CrestCore.Contracts;

/// A generated password's length is outside `Minimum` to `Maximum`.
public sealed record InvalidPasswordLength(int Minimum, int Maximum) : Rejection;
