namespace CrestCore.Contracts;

/// The intent names a page that is not open.
public sealed record UnknownPage(Guid PageId) : Rejection;
