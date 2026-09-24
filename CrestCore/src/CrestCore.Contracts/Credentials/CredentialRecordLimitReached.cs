namespace CrestCore.Contracts;

/// One question carried more than `Limit` records.
public sealed record CredentialRecordLimitReached(int Limit) : Rejection;
