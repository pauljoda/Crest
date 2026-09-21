namespace CrestCore.Domain;

/// Browser-owned URL spellings that are shared by address and tab policies.
public static class BrowserUrlConstants {
    #region Variables

    public const string AboutBlank = "about:blank";
    public const string ChromeScheme = "chrome";
    public const string CrestScheme = "crest";
    public const string ChromeExtensionScheme = "chrome-extension";
    public const string ChromePrefix = ChromeScheme + "://";
    public const string CrestPrefix = CrestScheme + "://";
    public const string ChromeExtensionPrefix = ChromeExtensionScheme + "://";

    #endregion
}
