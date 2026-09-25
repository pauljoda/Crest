namespace CrestCore.Contracts;

/// How the stored session's journal compares with `Cloud`, every record the
/// cloud holds, which the transport asks before it syncs with an account it has
/// not synced with yet. Refused as a `CloudSyncIntent` is, with
/// `NoStoredSession` or `StoredSessionClosed`.
[MessageLimit(64 * 1024 * 1024)]
public sealed record CloudComparison(IReadOnlyList<SyncRecord> Cloud) : Query<CloudContentComparison>;
