namespace CrestCore.Contracts;

/// Replaces the session's synced content and its journal with the cloud's
/// records, as the person chose. Nothing waits to upload afterwards, and an
/// empty cloud leaves one new ordinary Space. What only this device keeps, its
/// app preferences and the Space deletions under way, stays.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ReplaceWithCloudRecords(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent;
