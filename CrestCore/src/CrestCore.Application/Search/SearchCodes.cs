using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for search engines, shared by the search policy operations.
/// Custom engines use the native record's field names.
internal static class SearchCodes {
    #region Variables

    public const string Id = "id";
    public const string Name = "name";
    public const string SearchTemplate = "searchURLTemplate";
    public const string SuggestionTemplate = "suggestionURLTemplate";
    private const int MaximumEditedLength = SearchProvider.MaximumTemplateLength * 2;

    #endregion

    #region Actions - Decoding

    /// The engine a query runs against: `{"id":"google"}` for a built-in, or a
    /// `custom:<uuid>` identity with its stored templates. A stored custom
    /// engine that no longer validates resolves to Google.
    public static SearchProvider Provider(JsonElement value) {
        Protocol.Members(value, Id, Name, SearchTemplate, SuggestionTemplate);
        string id = Protocol.Text(value, Id, 64);
        if (!id.StartsWith(SearchProvider.CustomPrefix, StringComparison.Ordinal)) {
            Protocol.Members(value, Id);
            return SearchProviderCatalog.BuiltIn(id) ?? throw new BrowserRuleException(BrowserRuleCodes.UnknownSearchProvider);
        }
        string identity = id[SearchProvider.CustomPrefix.Length..];
        if (!Guid.TryParseExact(identity, "D", out var guid) || identity != guid.ToString("D"))
            throw new ProtocolException(ProtocolErrorCodes.InvalidUuid);
        return SearchProviderCatalog.CustomOrDefault(guid, Edited(value, Name), Edited(value, SearchTemplate),
            OptionalEdited(value, SuggestionTemplate));
    }

    /// A custom engine as the person typed it, validated by the domain.
    public static SearchProvider Custom(JsonElement value) {
        Protocol.Members(value, Id, Name, SearchTemplate, SuggestionTemplate);
        return SearchProvider.Custom(Protocol.Id(value, Id), Edited(value, Name), Edited(value, SearchTemplate),
            OptionalEdited(value, SuggestionTemplate));
    }

    /// Text the person may have left empty or padded; the domain reports it.
    public static string Edited(JsonElement value, string field) {
        var member = value.GetProperty(field);
        if (member.ValueKind != JsonValueKind.String || member.GetString() is not { } text || text.Length > MaximumEditedLength)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return text;
    }

    public static string? OptionalEdited(JsonElement value, string field) =>
        value.TryGetProperty(field, out var member) && member.ValueKind != JsonValueKind.Null ? Edited(value, field) : null;

    public static SearchUrlPurpose Purpose(string value) => value switch {
        "search" => SearchUrlPurpose.Search,
        "suggestions" => SearchUrlPurpose.Suggestions,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidInput)
    };

    #endregion

    #region Actions - Encoding

    public static JsonObject IntentAnswer(AddressResolution? intent) => new() { ["url"] = intent?.Url, ["searchQuery"] = intent?.SearchQuery };

    public static JsonObject UrlAnswer(string? url) => new() { ["url"] = url };

    public static JsonObject RestoredAnswer(string? selectedId, IEnumerable<int> indices) => new() {
        ["selectedID"] = selectedId,
        ["indices"] = new JsonArray(indices.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray())
    };

    #endregion
}
