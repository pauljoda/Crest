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
    WorkspacePreview,
    WorkspaceReview,
    SessionRepair,
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
        "workspace.preview" => NativeSyncOperation.WorkspacePreview,
        "workspace.review" => NativeSyncOperation.WorkspaceReview,
        "session.repair" => NativeSyncOperation.SessionRepair,
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
        NativeSyncOperation.WorkspacePreview => "workspace.preview",
        NativeSyncOperation.WorkspaceReview => "workspace.review",
        NativeSyncOperation.SessionRepair => "session.repair",
        _ => throw new ArgumentOutOfRangeException(nameof(operation))
    };

    #endregion
}
