namespace CrestCore.Contracts;

/// The journal's current record for each of `Records`, as the cloud transport
/// uploads it. Refused as a `CloudSyncIntent` is, with `NoStoredSession` or
/// `StoredSessionClosed`.
public sealed record RecordsToUpload(IReadOnlyList<SyncRecordReference> Records) : Query<UploadBatch>;
