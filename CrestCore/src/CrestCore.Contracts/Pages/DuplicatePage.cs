namespace CrestCore.Contracts;

/// A page with this identity is already open.
public sealed record DuplicatePage(Guid PageId) : Rejection;
