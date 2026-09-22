using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// JSON command boundary for one process-local download ledger.
///
/// Every command answers a delta the native projection applies in place:
/// `applied` says whether the ledger accepted the event, `items` lists each
/// changed record with its index in newest-first order, and `removed` lists
/// removed record identities. The last answer is retained so the caller can
/// size its buffer after the command has run exactly once. Callers serialize
/// access; nothing here is persisted or synced.
public sealed class NativeDownloadLedger {
    #region Variables

    public const int MaximumInputBytes = 65_536;
    public const int MaximumOutputBytes = 4_194_304;

    private readonly DownloadLedger ledger = new();

    public IReadOnlyList<DownloadItem> Items => ledger.Items;

    /// The answer to the most recent command, or empty after a rejected one.
    public byte[] LastResult { get; private set; } = [];

    #endregion

    #region Actions - Commands

    public byte[] Apply(ReadOnlySpan<byte> utf8) {
        LastResult = [];
        if (utf8.Length > MaximumInputBytes) throw new ProtocolException(ProtocolErrorCodes.DownloadInputLimit);
        var request = Protocol.Parse(utf8);
        if (request.GetProperty("version").GetInt32() != 1) throw new ProtocolException(ProtocolErrorCodes.VersionMismatch);
        var result = Encoding.UTF8.GetBytes(Execute(DownloadCommandCodes.Parse(Protocol.Text(request, "command")), request).ToJsonString());
        if (result.Length > MaximumOutputBytes) throw new BrowserRuleException(BrowserRuleCodes.DownloadLedgerLimit);
        LastResult = result;
        return result;
    }

    private JsonObject Execute(DownloadCommand command, JsonElement request) {
        switch (command) {
            case DownloadCommand.Begin:
                Protocol.Members(request, "version", "command", "id", "profileID", "filename", "createdAt", "acknowledged");
                return Changed(ledger.Begin(Protocol.Id(request, "id"), Protocol.Id(request, "profileID"),
                    Protocol.Text(request, "filename", DownloadLedger.MaximumFilenameLength),
                    request.GetProperty("createdAt").GetDouble(), request.GetProperty("acknowledged").GetBoolean()));
            case DownloadCommand.Destination:
                Protocol.Members(request, "version", "command", "id", "destination", "filename");
                return Changed(ledger.SetDestination(Protocol.Id(request, "id"),
                    Protocol.Text(request, "destination", DownloadLedger.MaximumDestinationLength),
                    Protocol.Text(request, "filename", DownloadLedger.MaximumFilenameLength)));
            case DownloadCommand.Transfer:
                Protocol.Members(request, "version", "command", "id", "telemetry", "progress");
                return Changed(ledger.RecordTransfer(Protocol.Id(request, "id"),
                    DownloadCodes.ParseTelemetry(request.GetProperty("telemetry")), request.GetProperty("progress").GetDouble()));
            case DownloadCommand.AssessRisk:
                Protocol.Members(request, "version", "command", "id", "assessment");
                var assessment = request.GetProperty("assessment");
                Protocol.Members(assessment, "sanitizedFilename", "reasons");
                var reasons = assessment.GetProperty("reasons").EnumerateArray().Select(DownloadCodes.ParseReason).Distinct().ToArray();
                return Changed(ledger.AssessRisk(Protocol.Id(request, "id"), new(
                    Protocol.Text(assessment, "sanitizedFilename", DownloadLedger.MaximumFilenameLength), reasons)));
            case DownloadCommand.Finish:
                Protocol.Members(request, "version", "command", "id", "finalByteCount");
                return Changed(ledger.Finish(Protocol.Id(request, "id"), DownloadCodes.Optional(request, "finalByteCount")?.GetInt64()));
            case DownloadCommand.Fail or DownloadCommand.Cancel:
                Protocol.Members(request, "version", "command", "id", "message");
                var message = Protocol.Text(request, "message", DownloadLedger.MaximumMessageLength);
                return Changed(command == DownloadCommand.Fail
                    ? ledger.Fail(Protocol.Id(request, "id"), message)
                    : ledger.Cancel(Protocol.Id(request, "id"), message));
            case DownloadCommand.AwaitApproval or DownloadCommand.Block or DownloadCommand.Restart:
                Protocol.Members(request, "version", "command", "id");
                var id = Protocol.Id(request, "id");
                return Changed(command switch {
                    DownloadCommand.AwaitApproval => ledger.AwaitApproval(id),
                    DownloadCommand.Block => ledger.BlockAutomaticDownload(id),
                    _ => ledger.Restart(id)
                });
            case DownloadCommand.AcknowledgeProfile:
                Protocol.Members(request, "version", "command", "profileID");
                var acknowledged = ledger.AcknowledgeProfile(Protocol.Id(request, "profileID"));
                return Delta(acknowledged.Count > 0, acknowledged, []);
            case DownloadCommand.Remove:
                Protocol.Members(request, "version", "command", "id");
                var removedID = Protocol.Id(request, "id");
                bool removed = ledger.Remove(removedID);
                return Delta(removed, [], removed ? [removedID] : []);
            case DownloadCommand.RemoveProfile:
                Protocol.Members(request, "version", "command", "profileID");
                return Removed(ledger.RemoveProfile(Protocol.Id(request, "profileID")));
            default:
                Protocol.Members(request, "version", "command", "now", "retention");
                var limits = request.GetProperty("retention").EnumerateArray().Select(limit => {
                    Protocol.Members(limit, "profileID", "lifetime");
                    return new DownloadRetentionLimit(Protocol.Id(limit, "profileID"), DownloadCodes.Optional(limit, "lifetime")?.GetDouble());
                }).ToArray();
                return Removed(ledger.RemoveExpired(limits, request.GetProperty("now").GetDouble()));
        }
    }

    private JsonObject Changed(DownloadItem? item) => item is null ? Delta(false, [], []) : Delta(true, [item], []);

    private JsonObject Removed(IReadOnlyList<Guid> identities) => Delta(identities.Count > 0, [], identities);

    private JsonObject Delta(bool applied, IReadOnlyList<DownloadItem> changed, IReadOnlyList<Guid> removed) => new() {
        ["applied"] = applied,
        ["items"] = new JsonArray(changed.Select(item => (JsonNode?)new JsonObject {
            ["index"] = ledger.IndexOf(item.Id),
            ["item"] = DownloadCodes.Item(item)
        }).ToArray()),
        ["removed"] = new JsonArray(removed.Select(id => (JsonNode?)JsonValue.Create(id.ToString())).ToArray())
    };

    #endregion
}
