namespace CrestCore.Contracts;

/// A download or its profile has an empty identity.
public sealed record InvalidDownloadIdentity() : Rejection;
