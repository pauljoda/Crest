using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Search providers

    /// Adds, edits or removes one of a Space's custom search engines through
    /// the domain rules, changing only the search part of its preferences.
    /// Upsert arguments: `provider` (`id`, `name`, `searchURLTemplate`,
    /// `suggestionURLTemplate`) and `selects`. Remove arguments: `id`.
    private static BrowsingPreferences EditSearchProviders(SessionOperation operation, BrowsingPreferences preferences, JsonObject args) {
        var search = SearchPreferences.Restore(preferences);
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
        return search.Applied(preferences);
    }

    #endregion
}
