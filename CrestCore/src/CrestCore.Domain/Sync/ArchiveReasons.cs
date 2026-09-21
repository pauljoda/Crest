namespace CrestCore.Domain;

/// Stable archive reason codes used by the session and sync wire formats.
public static class ArchiveReasons {
    #region Variables

    public const string Closed = "closed";
    public const string Deleted = "deleted";
    public const string DeletedOnAnotherDevice = "deletedOnAnotherDevice";
    public const string AutoCleanup = "autoCleanup";
    public const string QuickWindow = "quickWindow";
    public const string Synced = "synced";

    #endregion
}
