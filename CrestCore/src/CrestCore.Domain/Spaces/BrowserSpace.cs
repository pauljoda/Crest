namespace CrestCore.Domain;

/// Rules every Space applies to the names and addresses it holds.
public static class BrowserSpace {
    #region Variables

    public const int MaximumTabs = 5000;
    /// The most characters a Space or folder name holds.
    public const int MaximumNameLength = 200;

    #endregion

    #region Actions - Validation

    public static string ValidName(string name) {
        name = name.Trim();
        if (name.Length is 0 or > MaximumNameLength) throw new BrowserRuleException(BrowserRuleCodes.InvalidName);
        return name;
    }

    public static void ValidateUrl(string? url, bool allowsInternalPages = false) {
        if (url is null || url.Length > 16384 || !Uri.TryCreate(url, UriKind.Absolute, out var parsed)
            || ((parsed.Scheme != Uri.UriSchemeHttp && parsed.Scheme != Uri.UriSchemeHttps)
                && url != BrowserUrlConstants.AboutBlank
                // A local document is a legitimate tab URL on every engine. It stays
                // out of sync, which the sync projection decides by scheme, not here.
                && !(parsed.Scheme == Uri.UriSchemeFile && parsed.Host.Length == 0 && parsed.AbsolutePath.Length > 0)
                && !(allowsInternalPages && (parsed.Scheme == BrowserUrlConstants.ChromeScheme
                    || parsed.Scheme == BrowserUrlConstants.CrestScheme) && parsed.Host.Length > 0)
                && !(allowsInternalPages && parsed.Scheme == BrowserUrlConstants.ChromeExtensionScheme && parsed.Host.Length == 32
                    && parsed.Host.All(c => c is >= 'a' and <= 'p')))
            || !string.IsNullOrEmpty(parsed.UserInfo))
            throw new BrowserRuleException(BrowserRuleCodes.UnsupportedUrl);
    }

    #endregion
}
