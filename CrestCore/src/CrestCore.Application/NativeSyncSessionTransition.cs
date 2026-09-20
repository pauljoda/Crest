using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Prepares the session and journal together. Local edits stage before incoming
/// records; repair and retention finish before either resulting value is returned.
/// Publication and durable storage must accept this pair together.
public sealed record NativeSyncSessionTransition(NativeSyncJournal Journal, JsonObject Materialization)
{
    public static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, ReadOnlySpan<byte> input)
    {
        if (input.Length is 0 or > NativeSyncJournal.MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
        bool replacing = request["operation"]!.GetValue<string>() switch
        { "merge" => false, "replace" => true, _ => throw new BrowserRuleException("unknown_sync_operation") };
        double now = request["now"]!.GetValue<double>();
        if (!double.IsFinite(now)) throw new BrowserRuleException("invalid_saved_date");
        var preferences = request["preferences"]!;
        var local = request["session"]!.AsObject();
        var incoming = request["records"]!.AsArray();
        var next = journal;
        void Apply(string operation, JsonObject args)
        {
            next = next.Apply(Encoding.UTF8.GetBytes(new JsonObject { ["version"] = 1, ["operation"] = operation,
                ["preferences"] = preferences.DeepClone(), ["arguments"] = args }.ToJsonString()));
        }
        void Stage(JsonObject session, string reason) => Apply("stage", new JsonObject
        { ["session"] = session.DeepClone(), ["deletionReason"] = reason, ["now"] = now });
        if (!replacing && local["disposableSeedMarker"] is null) Stage(local, "superseded");
        Apply(replacing ? "replace" : "merge", new JsonObject { ["records"] = incoming.DeepClone() });
        var raw = replacing && incoming.Count == 0
            ? new JsonObject { ["spaces"] = new JsonArray() }
            : NativeSyncMaterializer.Materialize(local, preferences,
                NativeSyncEvaluator.Reconcile(next.Records).Select(n => n!.AsObject()).ToArray(), now);
        var repaired = NativeSessionMaintenance.Repair(raw, now, request["emptySpace"] as JsonObject);
        var retained = NativeSessionMaintenance.Retain(repaired["session"]!.AsObject(), now);
        bool removed = retained["changed"]!.GetValue<bool>();
        repaired["session"] = retained["session"]!.DeepClone();
        // Cleanup already authorized on this device must survive remote deletion,
        // replacement and retention until its local adapters acknowledge it.
        if (local["spaceDeletions"] is JsonArray pending && pending.Count > 0)
        {
            var result = repaired["session"]!.AsObject();
            result["spaceDeletions"] = pending.DeepClone();
            var spaces = result["spaces"]!.AsArray();
            foreach (var intent in pending)
            {
                var id = NativeSessionAuthority.Id(intent!["spaceID"]);
                var original = local["spaces"]!.AsArray().Single(s => NativeSessionAuthority.Id(s!["id"]) == id)!;
                var existing = spaces.FirstOrDefault(s => NativeSessionAuthority.Id(s!["id"]) == id);
                if (existing is not null) spaces[spaces.IndexOf(existing)] = original.DeepClone();
                else spaces.Add(original.DeepClone());
            }
        }
        if (!replacing || removed) Stage(repaired["session"]!.AsObject(), removed ? "retention" : "superseded");
        return new(next, repaired);
    }
}
