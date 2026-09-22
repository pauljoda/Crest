using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// A prepared query is evaluated once, then read without repeating projection
/// work or generating different identities during buffer-capacity negotiation.
public static class NativeSyncQuery {
    #region Variables

    public const int MaximumBytes = NativeSyncJournal.MaximumBytes;

    #endregion

    #region Actions - Queries

    public static byte[] Prepare(ReadOnlySpan<byte> input) {
        if (input.Length is 0 or > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        JsonObject result;
        try {
            JsonNode value = NativeSyncOperationCodes.Parse(request["operation"]!.GetValue<string>()) switch {
                NativeSyncOperation.BatchPreview => PreviewBatch(request),
                NativeSyncOperation.TransferPreview => NativeTabTransfer.Evaluate(request["source"]!.AsObject(), request["destination"]!.AsObject(),
                    request["arguments"]!.AsObject(), request["now"]!.GetValue<double>()),
                NativeSyncOperation.Project => NativeSyncProjection.Project(request["session"]!.AsObject(), request["preferences"]!,
                    request["records"]!.AsArray().Select(n => n!.AsObject())),
                NativeSyncOperation.Materialize => Materialize(request),
                NativeSyncOperation.WorkspacePreview => NativeWorkspaceImport.Preview(request["session"]!.AsObject(), request["arguments"]!.AsObject(),
                    request["mode"]!.GetValue<string>(), request["now"]!.GetValue<double>()),
                NativeSyncOperation.SessionRepair => NativeSessionMaintenance.Repair(request["session"]!.AsObject(), request["now"]!.GetValue<double>(),
                    request["emptySpace"] as JsonObject),
                NativeSyncOperation.SessionRetain => NativeSessionMaintenance.Retain(request["session"]!.AsObject(), request["now"]!.GetValue<double>()),
                _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownSyncOperation)
            };
            result = new() { ["value"] = value };
        } catch (NativeSyncDocumentException error) {
            return Failure(error);
        }
        var bytes = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (bytes.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        return bytes;
    }

    private static JsonNode PreviewBatch(JsonObject request) {
        var core = new NativeSessionAuthority(Encoding.UTF8.GetBytes(request["session"]!.ToJsonString()));
        var command = request["command"]!.AsObject();
        return JsonNode.Parse(core.PrepareCommand(1, Encoding.UTF8.GetBytes(command.ToJsonString())).Output)!;
    }

    private static JsonObject Materialize(JsonObject request) {
        double now = request["now"]!.GetValue<double>();
        var session = NativeSyncMaterializer.Materialize(request["session"]!.AsObject(), request["preferences"]!,
            NativeSyncEvaluator.Reconcile(request["records"]!.AsArray().Select(n => n!.AsObject()))
                .Select(n => n!.AsObject()).ToArray(), now);
        return NativeSessionMaintenance.Repair(session, now, request["emptySpace"] as JsonObject);
    }

    public static byte[] Failure(NativeSyncDocumentException error) => Encoding.UTF8.GetBytes(new JsonObject { ["error"] = new JsonObject { ["code"] = error.Code, ["value"] = error.Value } }.ToJsonString());

    public static byte[] Success(JsonNode value) {
        var bytes = Encoding.UTF8.GetBytes(new JsonObject { ["value"] = value }.ToJsonString());
        if (bytes.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        return bytes;
    }

    #endregion
}
