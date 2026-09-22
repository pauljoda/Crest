using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Variables

    private const int MaximumQueryLength = 4096;
    private const int MaximumStoredProviders = SearchPreferences.MaximumCustomProviders * 2;

    #endregion

    #region Actions - Search

    /// Null when the operation is not an address or search policy.
    private static JsonObject? EvaluateSearch(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.AddressIntent:
                Protocol.Members(request, "version", "operation", "input", "searchProvider", "allowsInternalPages");
                // An empty address is a successful no-navigation decision.
                var input = request.GetProperty("input").GetString() ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                var provider = SearchCodes.Provider(request.GetProperty("searchProvider"));
                bool allowsInternalPages = Optional(request, "allowsInternalPages")?.GetBoolean() ?? false;
                var intent = AddressResolution.Resolve(input, provider, allowsInternalPages);
                return new() { ["url"] = intent?.Url, ["searchQuery"] = intent?.SearchQuery };
            case PolicyOperation.SearchUrl:
                Protocol.Members(request, "version", "operation", "searchProvider", "query", "purpose");
                var engine = SearchCodes.Provider(request.GetProperty("searchProvider"));
                var query = SearchCodes.Edited(request, "query");
                if (query.Length > MaximumQueryLength) throw new ProtocolException(ProtocolErrorCodes.InvalidString);
                return new() {
                    ["url"] = Protocol.Text(request, "purpose", 16) switch {
                        "search" => engine.Search(query),
                        "suggestions" => engine.Suggest(query),
                        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidInput)
                    }
                };
            case PolicyOperation.SearchCustomProvider:
                Protocol.Members(request, "version", "operation", "provider", "existing");
                var existing = new List<(string Id, string Name)>();
                foreach (var item in request.GetProperty("existing").EnumerateArray()) {
                    Protocol.Members(item, SearchCodes.Id, SearchCodes.Name);
                    existing.Add((SearchProvider.CustomId(Protocol.Id(item, SearchCodes.Id)), SearchCodes.Edited(item, SearchCodes.Name)));
                    if (existing.Count > MaximumStoredProviders) throw new ProtocolException(ProtocolErrorCodes.SearchProviderBatchLimit);
                }
                try {
                    var custom = SearchCodes.Custom(request.GetProperty("provider"));
                    SearchPreferences.RequireAdmissible(custom, existing);
                    return new() { ["provider"] = SearchCodes.Custom(custom) };
                } catch (BrowserRuleException error) {
                    // The editor explains the specific rule the person broke.
                    return new() { ["error"] = error.Code };
                }
            case PolicyOperation.SearchCustomProviders:
                Protocol.Members(request, "version", "operation", "selectedID", "providers");
                var stored = new List<(int Index, SearchProvider Provider)>();
                int index = 0;
                foreach (var item in request.GetProperty("providers").EnumerateArray()) {
                    if (index >= MaximumStoredProviders) throw new ProtocolException(ProtocolErrorCodes.SearchProviderBatchLimit);
                    try {
                        stored.Add((index, SearchCodes.Custom(item)));
                    } catch (BrowserRuleException) {
                        // A stored engine that no longer validates is left out, never run.
                    }
                    index++;
                }
                var restored = SearchPreferences.Restore(Protocol.OptionalText(request, "selectedID", 64),
                    stored.Select(entry => entry.Provider), false);
                var kept = restored.CustomProviders.Select(provider => stored.First(entry => ReferenceEquals(entry.Provider, provider)).Index);
                return new() {
                    ["selectedID"] = restored.SelectedId,
                    ["indices"] = new JsonArray(kept.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray())
                };
            default:
                return null;
        }
    }

    #endregion
}
