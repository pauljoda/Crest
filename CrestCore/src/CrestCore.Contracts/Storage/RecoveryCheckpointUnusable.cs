namespace CrestCore.Contracts;

/// The recovery checkpoint cannot be restored: there is none, it does not hold
/// a complete session and journal, or it could not be put in place. A restore
/// that stops after it began setting the file aside leaves the restore marker,
/// so the directory stays refused until a restore completes.
public sealed record RecoveryCheckpointUnusable(StorageFailure Reason) : Rejection;
