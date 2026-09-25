namespace CrestCore.Contracts;

/// The session's sync journal changed: the core staged the session's accepted
/// edits, took a merge or an acknowledged upload, or attached the journal it
/// loaded. When the session keeps a file the journal is on disk with them. The
/// journal holds `Records` records, and `PendingRecords` of them wait to
/// upload. The cloud transport schedules an upload when it hears this.
public sealed record SyncJournalChanged(Guid WorkspaceId, int PendingRecords, int Records) : Change;
