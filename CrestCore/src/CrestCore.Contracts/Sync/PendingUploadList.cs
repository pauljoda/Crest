namespace CrestCore.Contracts;

/// The records that wait to upload, in the order of their record names. None
/// while the stored session is the disposable seed a first launch made, which
/// never syncs.
public sealed record PendingUploadList(IReadOnlyList<SyncRecordReference> Records);
