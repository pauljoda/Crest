namespace CrestCore.Contracts;

/// A window is no longer open.
public sealed record WindowClosed(Guid WindowId) : Change;
