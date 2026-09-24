using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the address and search policy operations.
internal static class SearchPolicyRequests {
    #region Variables

    private const int MaximumQueryLength = 4096;
    private const int MaximumStoredProviders = SearchPreferences.MaximumCustomProviders * 2;

    #endregion

    #region Actions - Decoding

    /// An empty address is a successful no-navigation decision.
    public sealed record AddressIntent(string Input, SearchProvider Provider, bool AllowsInternalPages) {
        public static AddressIntent Decode(JsonElement request) {
            Members(request, "input", "searchProvider", "allowsInternalPages");
            var input = Element(request, "input").GetString() ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
            var provider = SearchCodes.Provider(Element(request, "searchProvider"));
            return new(input, provider, OptionalFlag(request, "allowsInternalPages") ?? false);
        }
    }

    public sealed record SearchUrl(SearchProvider Provider, string Query, SearchUrlPurpose Purpose) {
        public static SearchUrl Decode(JsonElement request) {
            Members(request, "searchProvider", "query", "purpose");
            var provider = SearchCodes.Provider(Element(request, "searchProvider"));
            var query = SearchCodes.Edited(request, "query");
            if (query.Length > MaximumQueryLength) throw new ProtocolException(ProtocolErrorCodes.InvalidString);
            return new(provider, query, SearchCodes.Purpose(Protocol.Text(request, "purpose", 16)));
        }
    }

    /// The stored custom engines by their position in the request. A stored
    /// engine that no longer validates is left out, never run.
    public sealed record CustomProviders(IReadOnlyList<(int Index, SearchProvider Provider)> Stored, string? SelectedId) {
        public static CustomProviders Decode(JsonElement request) {
            Members(request, "selectedID", "providers");
            var stored = new List<(int Index, SearchProvider Provider)>();
            int index = 0;
            foreach (var item in Element(request, "providers").EnumerateArray()) {
                if (index >= MaximumStoredProviders) throw new ProtocolException(ProtocolErrorCodes.SearchProviderBatchLimit);
                try {
                    stored.Add((index, SearchCodes.Custom(item)));
                } catch (BrowserRuleException) {
                    // Left out; see the summary.
                }
                index++;
            }
            return new(stored, Protocol.OptionalText(request, "selectedID", 64));
        }
    }

    #endregion
}
