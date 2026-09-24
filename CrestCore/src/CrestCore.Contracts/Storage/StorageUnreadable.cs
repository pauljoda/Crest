namespace CrestCore.Contracts;

/// The stored session could not be opened. Nothing was written to it.
public sealed record StorageUnreadable(StorageFailure Reason) : Rejection;
