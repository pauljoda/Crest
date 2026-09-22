namespace CrestCore.Application;

internal enum NativeSyncOperation {
    Unknown,
    Recover,
    Merge,
    Replace,
    Overwrite,
    Stage,
    Acknowledge,
    Preferences,
    Resolve,
    Reconcile,
    OrderAllocate,
    Project,
    Materialize,
    BatchPreview,
    TransferPreview,
    WorkspacePreview,
    SessionRepair,
    SessionRetain,
}

internal static class NativeSyncOperationCodes {
    #region Actions - Encoding

    public static NativeSyncOperation Parse(string? value) => value switch {
        "recover" => NativeSyncOperation.Recover,
        "merge" => NativeSyncOperation.Merge,
        "replace" => NativeSyncOperation.Replace,
        "overwrite" => NativeSyncOperation.Overwrite,
        "stage" => NativeSyncOperation.Stage,
        "acknowledge" => NativeSyncOperation.Acknowledge,
        "preferences" => NativeSyncOperation.Preferences,
        "resolve" => NativeSyncOperation.Resolve,
        "reconcile" => NativeSyncOperation.Reconcile,
        "order.allocate" => NativeSyncOperation.OrderAllocate,
        "project" => NativeSyncOperation.Project,
        "materialize" => NativeSyncOperation.Materialize,
        "batch.preview" => NativeSyncOperation.BatchPreview,
        "transfer.preview" => NativeSyncOperation.TransferPreview,
        "workspace.preview" => NativeSyncOperation.WorkspacePreview,
        "session.repair" => NativeSyncOperation.SessionRepair,
        "session.retain" => NativeSyncOperation.SessionRetain,
        _ => NativeSyncOperation.Unknown
    };

    public static string Name(NativeSyncOperation operation) => operation switch {
        NativeSyncOperation.Recover => "recover",
        NativeSyncOperation.Merge => "merge",
        NativeSyncOperation.Replace => "replace",
        NativeSyncOperation.Overwrite => "overwrite",
        NativeSyncOperation.Stage => "stage",
        NativeSyncOperation.Acknowledge => "acknowledge",
        NativeSyncOperation.Preferences => "preferences",
        NativeSyncOperation.Resolve => "resolve",
        NativeSyncOperation.Reconcile => "reconcile",
        NativeSyncOperation.OrderAllocate => "order.allocate",
        NativeSyncOperation.Project => "project",
        NativeSyncOperation.Materialize => "materialize",
        NativeSyncOperation.BatchPreview => "batch.preview",
        NativeSyncOperation.TransferPreview => "transfer.preview",
        NativeSyncOperation.WorkspacePreview => "workspace.preview",
        NativeSyncOperation.SessionRepair => "session.repair",
        NativeSyncOperation.SessionRetain => "session.retain",
        _ => throw new ArgumentOutOfRangeException(nameof(operation))
    };

    #endregion
}
