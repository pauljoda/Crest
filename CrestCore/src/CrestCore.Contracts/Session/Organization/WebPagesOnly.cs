namespace CrestCore.Contracts;

/// Only a page can join a split, and a Start Page is not one yet.
public sealed record WebPagesOnly(Guid TabId) : Rejection;
