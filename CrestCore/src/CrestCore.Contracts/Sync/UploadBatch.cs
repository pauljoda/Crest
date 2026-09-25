namespace CrestCore.Contracts;

/// What the journal holds of the records a transport asked for: `Records`, each
/// one it holds, in the order asked, and `Gone`, each one it no longer holds,
/// whose pending save the transport drops. While the stored session is the
/// disposable seed a first launch made, which never syncs, every record is gone.
public sealed record UploadBatch(IReadOnlyList<SyncRecord> Records, IReadOnlyList<SyncRecordReference> Gone);
