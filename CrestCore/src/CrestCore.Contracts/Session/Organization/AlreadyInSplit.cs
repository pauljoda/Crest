namespace CrestCore.Contracts;

/// The tab is already a member of that split.
public sealed record AlreadyInSplit(Guid TabId) : Rejection;
