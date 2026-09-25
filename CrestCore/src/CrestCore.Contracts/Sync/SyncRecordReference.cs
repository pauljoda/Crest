namespace CrestCore.Contracts;

/// One synced record by identity: its kind, and the identity it has as that
/// kind. A tab and the archive entry it becomes share an identity, so the kind
/// tells them apart.
public sealed record SyncRecordReference(SyncRecordKind Kind, Guid Id);
