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
/// so no migration is needed. A capability and a decision are spelled as
/// their set's `Name`. The permission ledger's JSON and the origin policies
/// spell an origin as a record does, `{"scheme": …, "host": …, "port": …}`.
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
    private const string Scheme = "scheme";
    private const string Host = "host";
    private const string Port = "port";

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
            [Origin] = EncodeOrigin(record.Origin),
            [Permission] = record.Permission.Name
        };
        if (record.Detail is { } detail) value[Detail] = detail;
        value[Decision] = record.Decision.Name;
        value[ModifiedAt] = record.ModifiedAt;
        return value;
    }

    private static SitePermissionRecord? Record(JsonElement item) {
        try {
            if (item.ValueKind != JsonValueKind.Object) return null;
            var space = item.GetProperty(Space);
            var origin = item.GetProperty(Origin);
            if (SitePermission.Named(item.GetProperty(Permission).GetString()) is not { } permission
                || SitePermissionDecision.Named(item.GetProperty(Decision).GetString()) is not { } decision) return null;
            string? detail = item.TryGetProperty(Detail, out var stored) && stored.ValueKind != JsonValueKind.Null ? stored.GetString() : null;
            return new(Identity(item.GetProperty(Id)), Identity(space.ValueKind == JsonValueKind.Object ? space.GetProperty(RawValue) : space),
                new(origin.GetProperty(Scheme).GetString() ?? "", origin.GetProperty(Host).GetString() ?? "",
                    origin.GetProperty(Port).GetInt32()),
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

    #region Actions - Requests

    /// A decision a request names by its saved spelling.
    public static SitePermissionDecision DecodeDecision(JsonElement request, string field) =>
        SitePermissionDecision.Named(Protocol.Text(request, field, 64))
        ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPermissionDecision);

    #endregion

    #region Actions - Origins

    /// An origin in the record's shape.
    public static JsonObject EncodeOrigin(SiteOrigin origin) => new() {
        [Scheme] = origin.Scheme,
        [Host] = origin.Host,
        [Port] = origin.Port
    };

    /// An origin a platform reported in a request, which must be exactly the
    /// record's shape; the domain lowercases it and fills in the default web port.
    public static SiteOrigin DecodeOrigin(JsonElement value) {
        Protocol.Members(value, Scheme, Host, Port);
        return new(Protocol.Text(value, Scheme, SiteOrigin.MaximumSchemeLength), Protocol.Text(value, Host, SiteOrigin.MaximumHostLength),
            value.GetProperty(Port).GetInt32());
    }

    public static SiteOrigin? DecodeOptionalOrigin(JsonElement request, string field) =>
        request.TryGetProperty(field, out var value) && value.ValueKind != JsonValueKind.Null ? DecodeOrigin(value) : null;

    #endregion
}
