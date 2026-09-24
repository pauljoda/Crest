namespace CrestCore.Contracts;

/// The tab already owns `PageId`; a tab owns one page at a time.
public sealed record TabAlreadyHasPage(Guid TabId, Guid PageId) : Rejection;
