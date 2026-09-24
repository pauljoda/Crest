namespace CrestCore.Contracts;

/// The order does not name each of the workspace's Spaces exactly once.
public sealed record InvalidSpaceOrder() : Rejection;
