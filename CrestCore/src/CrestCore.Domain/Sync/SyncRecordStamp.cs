namespace CrestCore.Domain;

public sealed record SyncRecordStamp(string Kind, Guid Id, Guid Space, SyncVersion Version,
    string? DeletionReason, double? DeletedAt, double? ActivatedAt);
