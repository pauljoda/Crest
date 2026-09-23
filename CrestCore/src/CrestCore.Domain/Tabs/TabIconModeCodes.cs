using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Stable icon-mode spellings in native session records and tab edits.
public static class TabIconModeCodes {
    #region Actions - Decoding

    /// Null for a term this build cannot name, so the caller decides whether
    /// that means "derive the mode" or "reject the edit".
    public static TabIconMode? Parse(string? value) => value switch {
        "automatic" => TabIconMode.Automatic,
        "pulled" => TabIconMode.Pulled,
        "emoji" => TabIconMode.Emoji,
        _ => null
    };

    #endregion

    #region Actions - Encoding

    public static string Name(TabIconMode mode) => mode switch {
        TabIconMode.Automatic => "automatic",
        TabIconMode.Pulled => "pulled",
        TabIconMode.Emoji => "emoji",
        _ => throw new BrowserRuleException(BrowserRuleCodes.InvalidTabIcon)
    };

    #endregion
}
