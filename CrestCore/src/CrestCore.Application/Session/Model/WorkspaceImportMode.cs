namespace CrestCore.Application;

internal enum WorkspaceImportMode { Unknown, Portable, Manual, Review }

internal static class WorkspaceImportModeCodes {
    #region Actions - Decoding

    public static WorkspaceImportMode Parse(string? value) => value switch {
        "portable" => WorkspaceImportMode.Portable,
        "manual" => WorkspaceImportMode.Manual,
        "review" => WorkspaceImportMode.Review,
        _ => WorkspaceImportMode.Unknown
    };

    #endregion
}
