namespace CrestCore.Contracts;

/// A page's navigation history in its engine's own format, or nothing before
/// the page's first commit.
public sealed record InteractionState(byte[]? State);
