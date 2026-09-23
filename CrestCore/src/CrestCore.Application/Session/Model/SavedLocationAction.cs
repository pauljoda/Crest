namespace CrestCore.Application;

internal enum SavedLocationAction { Unknown, Replace, Restore }

internal static class SavedLocationActionCodes {
    #region Actions - Decoding

    public static SavedLocationAction Parse(string? value) => value switch {
        "replace" => SavedLocationAction.Replace,
        "restore" => SavedLocationAction.Restore,
        _ => SavedLocationAction.Unknown
    };

    #endregion
}
