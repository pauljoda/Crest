namespace CrestCore.Contracts;

/// One synced record as the transport carries it: its kind and identity, the
/// Space it belongs to, the version that wrote it, and its body, which is its
/// tombstone when `IsTombstone` and its payload otherwise. The body is the
/// journal's JSON, with dates in seconds since 2001, and only the core reads it.
public sealed record SyncRecord(SyncRecordKind Kind, Guid Id, Guid SpaceId, SyncVersion Version, byte[] Body, bool IsTombstone);
