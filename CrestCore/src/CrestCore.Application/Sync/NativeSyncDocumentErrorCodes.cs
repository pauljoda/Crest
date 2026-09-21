namespace CrestCore.Application;

/// Stable error codes returned by sync document queries.
internal static class NativeSyncDocumentErrorCodes {
    #region Variables

    internal const string DanglingFolder = "danglingFolder";
    internal const string DuplicateProfile = "duplicateProfile";
    internal const string DuplicateRecord = "duplicateRecord";
    internal const string ImmutableProfileChanged = "immutableProfileChanged";
    internal const string InvalidFolderHierarchy = "invalidFolderHierarchy";
    internal const string RecordLimitExceeded = "recordLimitExceeded";
    internal const string TooManyPinnedTabs = "tooManyPinnedTabs";

    #endregion
}
