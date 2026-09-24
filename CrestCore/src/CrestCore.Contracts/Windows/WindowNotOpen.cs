namespace CrestCore.Contracts;

/// The intent names a window that is not open.
public sealed record WindowNotOpen(Guid WindowId) : Rejection;
