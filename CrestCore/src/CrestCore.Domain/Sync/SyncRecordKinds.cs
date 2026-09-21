namespace CrestCore.Domain;

/// Stable kinds used to identify portable sync records.
public static class SyncRecordKinds {
    #region Variables

    public const string Space = "space";
    public const string Folder = "folder";
    public const string Tab = "tab";
    public const string History = "history";
    public const string Archive = "archive";

    #endregion

    #region Actions - Validation

    public static bool Includes(string? kind)
        => kind is Space or Folder or Tab or History or Archive;

    #endregion
}
