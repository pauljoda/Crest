namespace CrestCore.Contracts;

/// The core staged the session's accepted edits in its sync journal, which is
/// on disk with them when the session keeps a file. `PendingRecords` records
/// wait to upload. The cloud transport schedules an upload when it hears this.
public sealed record SyncJournalChanged(Guid WorkspaceId, int PendingRecords) : Change;
