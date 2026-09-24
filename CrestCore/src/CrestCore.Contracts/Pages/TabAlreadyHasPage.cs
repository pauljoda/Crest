namespace CrestCore.Contracts;

/// The tab already owns `PageId` in this window; a window hosts one page for a
/// tab at a time. Windows that share their pages reuse that one, and a window
/// with pages of its own, as each iPad scene has, opens its own.
public sealed record TabAlreadyHasPage(Guid TabId, Guid PageId) : Rejection;
