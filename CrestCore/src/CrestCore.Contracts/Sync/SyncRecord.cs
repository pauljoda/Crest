namespace CrestCore.Contracts;

/// One synced record as the transport carries it: its kind and identity, the
/// Space it belongs to, the version that wrote it, the oldest CloudKit schema
/// whose clients read it whole, and its body, which is its tombstone when
/// `IsTombstone` and its payload otherwise. The body is the CloudKit field as
/// the cloud stores it, with dates in seconds since 1970, and only the core
/// reads or writes it.
public sealed record SyncRecord(SyncRecordKind Kind, Guid Id, Guid SpaceId, SyncVersion Version, int Schema, byte[] Body, bool IsTombstone);
