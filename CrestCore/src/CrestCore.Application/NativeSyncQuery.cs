using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A prepared query is evaluated once, then read without repeating projection
/// work or generating different identities during buffer-capacity negotiation.
public static class NativeSyncQuery
{
    public const int MaximumBytes = NativeSyncJournal.MaximumBytes;
    public static byte[] Prepare(ReadOnlySpan<byte> input)
    {
        if (input.Length is 0 or > MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
        JsonObject result;
        try
        {
            JsonNode value = request["operation"]!.GetValue<string>() switch
            {
                "project" => NativeSyncProjection.Project(request["session"]!.AsObject(), request["preferences"]!,
                    request["records"]!.AsArray().Select(n => n!.AsObject())),
                "materialize" => NativeSyncMaterializer.Materialize(request["session"]!.AsObject(), request["preferences"]!,
                    NativeSyncEvaluator.Reconcile(request["records"]!.AsArray().Select(n => n!.AsObject()))
                        .Select(n => n!.AsObject()).ToArray(), request["now"]!.GetValue<double>()),
                _ => throw new BrowserRuleException("unknown_sync_operation")
            };
            result = new() { ["value"] = value };
        }
        catch (NativeSyncDocumentException error)
        {
            return Failure(error);
        }
        var bytes = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (bytes.Length > MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        return bytes;
    }

    public static byte[] Failure(NativeSyncDocumentException error) => Encoding.UTF8.GetBytes(new JsonObject
    { ["error"] = new JsonObject { ["code"] = error.Code, ["value"] = error.Value } }.ToJsonString());
}
