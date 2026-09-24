namespace CrestCore.Application;

internal enum NativeSyncOperation {
    Unknown,
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
    SessionRepair,
}

internal static class NativeSyncOperationCodes {
    #region Actions - Encoding

    public static NativeSyncOperation Parse(string? value) => value switch {
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
        "session.repair" => NativeSyncOperation.SessionRepair,
        _ => NativeSyncOperation.Unknown
    };

    public static string Name(NativeSyncOperation operation) => operation switch {
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
        NativeSyncOperation.SessionRepair => "session.repair",
        _ => throw new ArgumentOutOfRangeException(nameof(operation))
    };

    #endregion

    #region Actions - Families

    /// The operations that stage the local session themselves, so a stage
    /// still queued has nothing left to add.
    public static bool SupersedesStaging(NativeSyncOperation operation) => operation is
        NativeSyncOperation.Merge
        or NativeSyncOperation.Replace
        or NativeSyncOperation.Overwrite;

    #endregion
}
