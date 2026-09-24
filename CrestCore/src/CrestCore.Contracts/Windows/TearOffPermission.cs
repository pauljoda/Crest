namespace CrestCore.Contracts;

/// Whether a dragged tab may leave its window, and when it may not, why.
public sealed record TearOffPermission(bool Allowed, TearOffRefusal? Reason);
