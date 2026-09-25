namespace CrestCore.Contracts;

/// Merges every record the cloud holds, as `MergeSyncRecords` merges a batch,
/// when the transport pulls the whole zone to recover. The snapshot is refused
/// whole with `InvalidSyncRecords` naming `UnreadablePayload` when any of its
/// records is one this build cannot read, so an incomplete snapshot never
/// decides what this device holds.
[MessageLimit(64 * 1024 * 1024)]
public sealed record MergeCloudSnapshot(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent;
