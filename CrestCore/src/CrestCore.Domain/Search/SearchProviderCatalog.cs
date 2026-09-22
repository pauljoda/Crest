namespace CrestCore.Domain;

/// The built-in search engines every Space offers, with their results and
/// suggestion templates. Native layers keep only titles and icons.
public static class SearchProviderCatalog {
    #region Variables

    public const string GoogleId = "google";
    public const string DuckDuckGoId = "duckDuckGo";

    public static SearchProvider Google { get; } = new(GoogleId, "Google",
        "https://www.google.com/search?q=%s", "https://www.google.com/complete/search?client=chrome&q=%s");

    public static IReadOnlyList<SearchProvider> BuiltIns { get; } = Array.AsReadOnly<SearchProvider>([
        Google,
        new(DuckDuckGoId, "DuckDuckGo", "https://duckduckgo.com/?q=%s", "https://duckduckgo.com/ac/?q=%s&type=list"),
        new("bing", "Bing", "https://www.bing.com/search?q=%s", "https://www.bing.com/osjson.aspx?query=%s"),
        new("ecosia", "Ecosia", "https://www.ecosia.org/search?q=%s", "https://ac.ecosia.org/autocomplete?q=%s&type=list"),
        new("brave", "Brave Search", "https://search.brave.com/search?q=%s", "https://search.brave.com/api/suggest?q=%s")
    ]);

    #endregion

    #region Actions - Lookup

    public static SearchProvider? BuiltIn(string id) => BuiltIns.FirstOrDefault(provider => provider.Id == id);

    /// A stored custom engine that no longer validates never runs its own
    /// template: queries go to Google, as the selection fallback does.
    public static SearchProvider CustomOrDefault(Guid id, string name, string search, string? suggestions) {
        try {
            return SearchProvider.Custom(id, name, search, suggestions);
        } catch (BrowserRuleException) {
            return Google;
        }
    }

    #endregion
}
