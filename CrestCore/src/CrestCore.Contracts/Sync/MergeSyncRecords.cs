namespace CrestCore.Contracts;

/// Merges records the cloud sent into the session and its journal. The
/// session's edits are staged first; each record the journal holds already
/// resolves against the one that arrived, field by field where the fields carry
/// their own clocks; the session is rebuilt from the reconciled records,
/// repaired, swept for retention and staged again. A Space tombstone for an
/// explicit deletion begins deleting that Space on this device. A record the
/// journal holds in another Space is refused.
[MessageLimit(64 * 1024 * 1024)]
public sealed record MergeSyncRecords(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent;
