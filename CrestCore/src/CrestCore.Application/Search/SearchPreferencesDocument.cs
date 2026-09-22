using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Reads and writes the search fields of a Space's persisted
/// `browsingPreferences`, leaving every other field as it was. The spelling
/// matches the native encoder, so checkpoints and sync records keep their format.
internal static class SearchPreferencesDocument {
    #region Variables

    private const string Selected = "selectedSearchProviderID";
    private const string LegacySelected = "searchProvider";
    private const string Custom = "customSearchProviders";
    private const string Suggestions = "searchSuggestionsEnabled";

    #endregion

    #region Actions - Persistence

    /// Stored custom engines that no longer validate are excluded, as the
    /// selection that named one falls back to Google.
    public static SearchPreferences Read(JsonObject? preferences) {
        var providers = new List<SearchProvider>();
        if (preferences?[Custom] is JsonArray custom)
            foreach (var item in custom) {
                if (item is not JsonObject value) continue;
                try {
                    providers.Add(SearchProvider.Custom(LegacySessionDocument.Id(value[SearchCodes.Id]),
                        LegacySessionDocument.Text(value[SearchCodes.Name]) ?? "",
                        LegacySessionDocument.Text(value[SearchCodes.SearchTemplate]) ?? "",
                        LegacySessionDocument.Text(value[SearchCodes.SuggestionTemplate])));
                } catch (BrowserRuleException) {
                    // Excluded, never run.
                }
            }
        return SearchPreferences.Restore(
            LegacySessionDocument.Text(preferences?[Selected]) ?? LegacySessionDocument.Text(preferences?[LegacySelected]),
            providers, preferences?[Suggestions]?.GetValue<bool>() ?? false);
    }

    /// Older builds read only `searchProvider`, so a custom selection keeps
    /// Google there as their safe fallback.
    public static void Write(JsonObject preferences, SearchPreferences search) {
        ArgumentNullException.ThrowIfNull(preferences);
        ArgumentNullException.ThrowIfNull(search);
        preferences[Selected] = search.SelectedId;
        preferences[LegacySelected] = search.SelectedId.StartsWith(SearchProvider.CustomPrefix, StringComparison.Ordinal)
            ? SearchProviderCatalog.GoogleId : search.SelectedId;
        preferences[Suggestions] = search.SuggestionsEnabled;
        preferences[Custom] = new JsonArray(search.CustomProviders.Select(provider => {
            var value = new JsonObject {
                [SearchCodes.Id] = Guid.Parse(provider.Id[SearchProvider.CustomPrefix.Length..]).ToString("D").ToUpperInvariant(),
                [SearchCodes.Name] = provider.Name,
                [SearchCodes.SearchTemplate] = provider.SearchTemplate
            };
            if (provider.SuggestionTemplate is { } suggestions) value[SearchCodes.SuggestionTemplate] = suggestions;
            return (JsonNode)value;
        }).ToArray());
    }

    #endregion
}
