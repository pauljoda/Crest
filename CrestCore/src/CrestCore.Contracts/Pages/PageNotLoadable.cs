namespace CrestCore.Contracts;

/// The page's engine holds no page to load into: it could not create it, or
/// the page closed.
public sealed record PageNotLoadable(Guid PageId) : Rejection;
