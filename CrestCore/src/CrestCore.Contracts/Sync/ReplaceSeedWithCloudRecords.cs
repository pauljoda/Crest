namespace CrestCore.Contracts;

/// Replaces the session with the cloud's records, as `ReplaceWithCloudRecords`
/// does, while it is still the disposable seed a first launch made. It changes
/// nothing once the seed is gone.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ReplaceSeedWithCloudRecords(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent;
