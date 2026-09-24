namespace CrestCore.Contracts;

/// The core could not stage the session's accepted edits for sync. The journal
/// is as it was; the next staged edit reports `SyncJournalChanged`.
public sealed record SyncStagingFailed(Guid WorkspaceId, SyncStagingFailure Reason) : Change;
