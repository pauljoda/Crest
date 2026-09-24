namespace CrestCore.Contracts;

/// The Space's archive holds no tab with this identity.
public sealed record UnknownArchivedTab(Guid TabId) : Rejection;
