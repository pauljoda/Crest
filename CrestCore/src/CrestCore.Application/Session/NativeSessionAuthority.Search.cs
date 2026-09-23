using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Search providers

    /// Adds, edits or removes one of a Space's custom search engines through
    /// the domain rules, rewriting only the search fields of its preferences.
    /// Upsert arguments: `provider` (`id`, `name`, `searchURLTemplate`,
    /// `suggestionURLTemplate`) and `selects`. Remove arguments: `id`.
    private static void EditSearchProviders(SessionOperation operation, JsonObject fields, JsonObject args) {
        var preferences = fields["browsingPreferences"] as JsonObject;
        if (preferences is null) {
            preferences = new JsonObject { ["currentTabCleanupPolicy"] = "after12Hours" };
            fields["browsingPreferences"] = preferences;
        }
        var search = SearchPreferencesDocument.Read(preferences);
        if (operation == SessionOperation.SpaceSearchProviderRemove) {
            search = search.Remove(Id(args[SearchCodes.Id]));
        } else {
            var value = args["provider"] as JsonObject ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchProvider);
            var provider = SearchProvider.Custom(Id(value[SearchCodes.Id]),
                StoredSessionCodec.Text(value[SearchCodes.Name]) ?? "",
                StoredSessionCodec.Text(value[SearchCodes.SearchTemplate]) ?? "",
                StoredSessionCodec.Text(value[SearchCodes.SuggestionTemplate]));
            search = search.Upsert(provider);
            if (args["selects"]?.GetValue<bool>() == true) search = search.Select(provider.Id, search.SuggestionsEnabled);
        }
        SearchPreferencesDocument.Write(preferences, search);
    }

    #endregion
}
