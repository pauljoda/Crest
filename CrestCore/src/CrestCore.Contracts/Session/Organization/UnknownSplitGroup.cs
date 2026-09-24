namespace CrestCore.Contracts;

/// No split in the Space has this identity, or it has fewer than two tabs.
public sealed record UnknownSplitGroup(Guid GroupId) : Rejection;
