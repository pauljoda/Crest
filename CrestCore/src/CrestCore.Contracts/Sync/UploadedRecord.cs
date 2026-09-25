namespace CrestCore.Contracts;

/// A record the cloud saved, at the version it saved.
public sealed record UploadedRecord(SyncRecordReference Record, SyncVersion Version);
