namespace CrestCore.Contracts;

/// A command whose sync journal is saved with it could not stage that journal,
/// so the core refused the command and changed nothing.
public sealed record SyncStagingRefused(SyncStagingFailure Reason) : Rejection;
