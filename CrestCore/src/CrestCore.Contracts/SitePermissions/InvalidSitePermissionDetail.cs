namespace CrestCore.Contracts;

/// A choice's detail is empty or longer than `Limit` characters.
public sealed record InvalidSitePermissionDetail(int Limit) : Rejection;
