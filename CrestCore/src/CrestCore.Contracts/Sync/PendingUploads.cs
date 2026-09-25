namespace CrestCore.Contracts;

/// Which records of the stored session's journal wait to upload. Refused as a
/// `CloudSyncIntent` is, with `NoStoredSession` or `StoredSessionClosed`.
public sealed record PendingUploads : Query<PendingUploadList>;
