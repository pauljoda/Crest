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

    #region Actions - Encoding

    public static string Name(SavedLocationAction action) => action switch {
        SavedLocationAction.Replace => "replace",
        SavedLocationAction.Restore => "restore",
        _ => throw new ArgumentOutOfRangeException(nameof(action))
    };

    #endregion
}
