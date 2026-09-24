namespace CrestCore.Contracts;

/// A restore from the recovery checkpoint did not finish. The core refuses the
/// directory until the restore completes, so a partial restore can never
/// become a fresh session.
public sealed record StorageRestoreInterrupted : Rejection;
