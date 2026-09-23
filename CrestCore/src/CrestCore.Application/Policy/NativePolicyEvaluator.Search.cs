using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.SearchPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Search

    /// Null when the operation is not an address or search policy.
    private static JsonObject? EvaluateSearch(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.AddressIntent => ResolveAddress(Requests.AddressIntent.Decode(request)),
        PolicyOperation.SearchUrl => SearchUrl(Requests.SearchUrl.Decode(request)),
        PolicyOperation.SearchCustomProvider => AdmitCustomProvider(Requests.CustomProvider.Decode(request)),
        PolicyOperation.SearchCustomProviders => RestoreCustomProviders(Requests.CustomProviders.Decode(request)),
        _ => null
    };

    private static JsonObject ResolveAddress(Requests.AddressIntent request) => SearchCodes.IntentAnswer(
        AddressResolution.Resolve(request.Input, request.Provider, request.AllowsInternalPages));

    private static JsonObject SearchUrl(Requests.SearchUrl request) => SearchCodes.UrlAnswer(request.Purpose switch {
        SearchUrlPurpose.Search => request.Provider.Search(request.Query),
        _ => request.Provider.Suggest(request.Query)
    });

    private static JsonObject AdmitCustomProvider(Requests.CustomProvider request) {
        // The editor explains the specific rule the person broke. A request
        // carries either the typed engine or the rule it broke.
        if (request.Provider is not { } provider) return PolicyAnswers.Error(request.Rejection!);
        try {
            SearchPreferences.RequireAdmissible(provider, request.Existing);
            return SearchCodes.ProviderAnswer(provider);
        } catch (BrowserRuleException error) {
            return PolicyAnswers.Error(error);
        }
    }

    private static JsonObject RestoreCustomProviders(Requests.CustomProviders request) {
        var restored = SearchPreferences.Restore(request.SelectedId, request.Stored.Select(entry => entry.Provider), false);
        var kept = restored.CustomProviders.Select(provider =>
            request.Stored.First(entry => ReferenceEquals(entry.Provider, provider)).Index);
        return SearchCodes.RestoredAnswer(restored.SelectedId, kept);
    }

    #endregion
}
