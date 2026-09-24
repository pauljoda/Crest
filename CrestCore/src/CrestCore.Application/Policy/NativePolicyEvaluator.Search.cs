using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.SearchPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Search

    /// Null when the operation is not an address or search policy. A Space's
    /// custom engines are admitted by the search-engine intents.
    private static JsonObject? EvaluateSearch(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.AddressIntent => ResolveAddress(Requests.AddressIntent.Decode(request)),
        PolicyOperation.SearchUrl => SearchUrl(Requests.SearchUrl.Decode(request)),
        PolicyOperation.SearchCustomProviders => RestoreCustomProviders(Requests.CustomProviders.Decode(request)),
        _ => null
    };

    private static JsonObject ResolveAddress(Requests.AddressIntent request) => SearchCodes.IntentAnswer(
        AddressResolution.Resolve(request.Input, request.Provider, request.AllowsInternalPages));

    private static JsonObject SearchUrl(Requests.SearchUrl request) =>
        SearchCodes.UrlAnswer(request.Purpose.Url(request.Provider, request.Query));

    private static JsonObject RestoreCustomProviders(Requests.CustomProviders request) {
        var restored = SearchPreferences.Restore(request.SelectedId, request.Stored.Select(entry => entry.Provider), false);
        var kept = restored.CustomProviders.Select(provider =>
            request.Stored.First(entry => ReferenceEquals(entry.Provider, provider)).Index);
        return SearchCodes.RestoredAnswer(restored.SelectedId, kept);
    }

    #endregion
}
