namespace CrestCore.Application;

/// Stable operation names shared by sync request writers and dispatchers.
internal static class NativeSyncOperations {
    #region Variables

    internal const string Recover = "recover";
    internal const string Merge = "merge";
    internal const string Replace = "replace";
    internal const string Overwrite = "overwrite";
    internal const string Stage = "stage";
    internal const string Acknowledge = "acknowledge";
    internal const string Preferences = "preferences";
    internal const string Resolve = "resolve";
    internal const string Reconcile = "reconcile";
    internal const string OrderAllocate = "order.allocate";
    internal const string Project = "project";
    internal const string Materialize = "materialize";

    #endregion
}
