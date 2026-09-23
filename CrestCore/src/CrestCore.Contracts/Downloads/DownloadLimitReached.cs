namespace CrestCore.Contracts;

/// The ledger already holds `Limit` records.
public sealed record DownloadLimitReached(int Limit) : Rejection;
