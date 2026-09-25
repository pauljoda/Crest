using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What conflict resolution reads of one version of a record. `ActivatedAt` is
/// when an open tab was last shown, and null for any other record.
public sealed record SyncRecordStamp(SyncRecordKind Kind, Guid Id, Guid Space, SyncVersion Version,
    SyncDeletionReason? DeletionReason, double? DeletedAt, double? ActivatedAt);
