using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed record SyncRecordStamp(string Kind, Guid Id, Guid Space, SyncVersion Version,
    SyncDeletionReason? DeletionReason, double? DeletedAt, double? ActivatedAt);
