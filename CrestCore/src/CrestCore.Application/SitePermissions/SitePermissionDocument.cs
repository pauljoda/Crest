using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The saved site-permission document: a JSON array of records in the format
/// the native store has always written under `crest.site-permissions.v1`.
/// Identities are uppercase UUIDs, the Space is `{"rawValue": …}`, a missing
/// `detail` is the site-wide rule and `modifiedAt` is seconds since 2001-01-01.
/// Existing documents load unchanged and are written back in the same shape,
/// so no migration is needed.
internal static class SitePermissionDocument {
    #region Variables

    private const string Id = "id";
    private const string Space = "spaceID";
    private const string RawValue = "rawValue";
    private const string Origin = "origin";
    private const string Permission = "permission";
    private const string Detail = "detail";
    private const string Decision = "decision";
    private const string ModifiedAt = "modifiedAt";

    #endregion

    #region Actions - Persistence

    /// Every record that still decodes. A document that is not JSON, or an
    /// entry this build cannot read, contributes nothing rather than failing
    /// the whole load.
    public static IReadOnlyList<SitePermissionRecord> Read(string? document) {
        if (string.IsNullOrEmpty(document)) return [];
        JsonDocument parsed;
        try {
            parsed = JsonDocument.Parse(document, new() { MaxDepth = 8 });
        } catch (JsonException) {
            return [];
        }
        using (parsed) {
            if (parsed.RootElement.ValueKind != JsonValueKind.Array) return [];
            var records = new List<SitePermissionRecord>();
            foreach (var item in parsed.RootElement.EnumerateArray()) {
                if (records.Count >= SitePermissionLedger.MaximumRecords) break;
                if (Record(item) is { } record) records.Add(record);
            }
            return records;
        }
    }

    public static string Write(IEnumerable<SitePermissionRecord> records) =>
        new JsonArray([.. records.Select(record => (JsonNode?)Encode(record))]).ToJsonString();

    /// One record in the saved format, which is also how the native
    /// projection decodes the records it lists.
    public static JsonObject Encode(SitePermissionRecord record) {
        var value = new JsonObject {
            [Id] = record.Id.ToString("D").ToUpperInvariant(),
            [Space] = new JsonObject { [RawValue] = record.Space.ToString("D").ToUpperInvariant() },
            [Origin] = SitePermissionCodes.Origin(record.Origin),
            [Permission] = SitePermissionCodes.Permission(record.Permission)
        };
        if (record.Detail is { } detail) value[Detail] = detail;
        value[Decision] = SitePermissionCodes.Decision(record.Decision);
        value[ModifiedAt] = record.ModifiedAt;
        return value;
    }

    private static SitePermissionRecord? Record(JsonElement item) {
        try {
            if (item.ValueKind != JsonValueKind.Object) return null;
            var space = item.GetProperty(Space);
            var origin = item.GetProperty(Origin);
            if (SitePermissionCodes.ParsePermission(item.GetProperty(Permission).GetString()) is not { } permission
                || SitePermissionCodes.TryParseDecision(item.GetProperty(Decision).GetString()) is not { } decision) return null;
            string? detail = item.TryGetProperty(Detail, out var stored) && stored.ValueKind != JsonValueKind.Null ? stored.GetString() : null;
            return new(Identity(item.GetProperty(Id)), Identity(space.ValueKind == JsonValueKind.Object ? space.GetProperty(RawValue) : space),
                new(origin.GetProperty(SitePermissionCodes.Scheme).GetString() ?? "", origin.GetProperty(SitePermissionCodes.Host).GetString() ?? "",
                    origin.GetProperty(SitePermissionCodes.Port).GetInt32()),
                permission, detail, decision, item.GetProperty(ModifiedAt).GetDouble());
        } catch (Exception error) when (error is BrowserRuleException or ProtocolException or InvalidOperationException
            or KeyNotFoundException or FormatException) {
            return null;
        }
    }

    private static Guid Identity(JsonElement value) =>
        Guid.TryParseExact(value.GetString(), "D", out var id) && id != Guid.Empty
            ? id : throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedIdentity);

    #endregion
}
