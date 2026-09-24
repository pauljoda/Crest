using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// JSON command boundary for one process-local site permission ledger.
///
/// `load` restores the saved document the native store read. Questions
/// (`decision`, `media_decision`, `records`) answer from the ledger. Commands
/// (`set`, `reset_record`, `reset_space`, `reset_session`) answer `applied`,
/// the complete saved `document` when it must be written again (otherwise
/// null), and the `changes` observers are told about. Every question and write
/// for a Space carries `locked`; a locked Space answers Ask, lists nothing and
/// records nothing. Session choices are never in the document. The last
/// answer is retained so the caller can size its buffer after the command
/// has run exactly once. Callers serialize access.
public sealed class NativeSitePermissionLedger {
    #region Variables

    public const int MaximumInputBytes = 4_194_304;
    public const int MaximumOutputBytes = 4_194_304;

    private readonly SitePermissionLedger ledger = new();

    public IReadOnlyList<SitePermissionRecord> PersistentRecords => ledger.PersistentRecords;

    /// The answer to the most recent command, or empty after a rejected one.
    public byte[] LastResult { get; private set; } = [];

    #endregion

    #region Actions - Commands

    public byte[] Apply(ReadOnlySpan<byte> utf8) {
        LastResult = [];
        if (utf8.Length > MaximumInputBytes) throw new ProtocolException(ProtocolErrorCodes.SitePermissionInputLimit);
        var request = Protocol.Parse(utf8);
        if (request.GetProperty("version").GetInt32() != 1) throw new ProtocolException(ProtocolErrorCodes.VersionMismatch);
        var result = Encoding.UTF8.GetBytes(Execute(SitePermissionCommandCodes.Parse(Protocol.Text(request, "command")), request).ToJsonString());
        if (result.Length > MaximumOutputBytes) throw new BrowserRuleException(BrowserRuleCodes.SitePermissionLedgerLimit);
        LastResult = result;
        return result;
    }

    private JsonObject Execute(SitePermissionCommand command, JsonElement request) {
        switch (command) {
            case SitePermissionCommand.Load:
                Protocol.Members(request, "version", "command", "document");
                var document = request.GetProperty("document");
                if (document.ValueKind is not (JsonValueKind.String or JsonValueKind.Null)) throw new ProtocolException(ProtocolErrorCodes.InvalidString);
                return new() { ["restored"] = ledger.Restore(SitePermissionDocument.Read(document.GetString())) };
            case SitePermissionCommand.Decision:
                Protocol.Members(request, "version", "command", "spaceID", "origin", "permission", "detail", "locked");
                return new() {
                    ["decision"] = ledger.Decision(Protocol.Id(request, "spaceID"), Origin(request), Permission(request),
                        Protocol.OptionalText(request, "detail", SitePermissionLedger.MaximumDetailLength), Locked(request)).Name
                };
            case SitePermissionCommand.MediaDecision:
                Protocol.Members(request, "version", "command", "spaceID", "origin", "media", "locked");
                return new() {
                    ["decision"] = ledger.MediaDecision(Protocol.Id(request, "spaceID"), Origin(request), Media(request),
                        Locked(request)).Name
                };
            case SitePermissionCommand.Records:
                Protocol.Members(request, "version", "command", "spaceID", "locked");
                return new() {
                    ["records"] = new JsonArray([.. ledger.Records(Protocol.Id(request, "spaceID"), Locked(request))
                        .Select(record => (JsonNode?)SitePermissionDocument.Encode(record))])
                };
            case SitePermissionCommand.Set:
                Protocol.Members(request, "version", "command", "spaceID", "origin", "permission", "detail", "decision",
                    "recordID", "now", "locked");
                return Outcome(ledger.Set(Protocol.Id(request, "spaceID"), Origin(request), Permission(request),
                    Protocol.OptionalText(request, "detail", SitePermissionLedger.MaximumDetailLength), Decision(request),
                    Protocol.Id(request, "recordID"), request.GetProperty("now").GetDouble(), Locked(request)));
            case SitePermissionCommand.ResetRecord:
                Protocol.Members(request, "version", "command", "id");
                return Outcome(ledger.ResetRecord(Protocol.Id(request, "id")));
            case SitePermissionCommand.ResetSpace:
                Protocol.Members(request, "version", "command", "spaceID");
                return Outcome(ledger.ResetSpace(Protocol.Id(request, "spaceID")));
            default:
                Protocol.Members(request, "version", "command");
                return Outcome(ledger.ResetSession());
        }
    }

    #endregion

    #region Actions - Requests

    private static bool Locked(JsonElement request) => request.GetProperty("locked").GetBoolean();

    private static SiteOrigin Origin(JsonElement request) => SitePermissionDocument.DecodeOrigin(request.GetProperty("origin"));

    private static SitePermission Permission(JsonElement request) =>
        SitePermission.Named(Protocol.Text(request, "permission", 64)) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidSitePermission);

    private static SitePermission Media(JsonElement request) =>
        SitePermission.Named(Protocol.Text(request, "media", 64)) is { IsMedia: true } media
            ? media : throw new ProtocolException(ProtocolErrorCodes.InvalidMediaPermission);

    private static SitePermissionDecision Decision(JsonElement request) => SitePermissionDocument.DecodeDecision(request, "decision");

    #endregion

    #region Actions - Answers

    private JsonObject Outcome(SitePermissionOutcome outcome) => new() {
        ["applied"] = outcome.Applied,
        ["document"] = outcome.PersistenceChanged ? SitePermissionDocument.Write(ledger.PersistentRecords) : null,
        ["changes"] = new JsonArray([.. outcome.Changes.Select(change => (JsonNode?)new JsonObject {
            ["spaceID"] = change.Space?.ToString("D"),
            ["origin"] = change.Origin is { } origin ? SitePermissionDocument.EncodeOrigin(origin) : null,
            ["permission"] = change.Permission?.Name,
            ["detail"] = change.Detail,
            ["revokesAuthorization"] = change.RevokesAuthorization
        })])
    };

    #endregion
}
