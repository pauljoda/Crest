using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Prepares the session and journal together. Local edits stage before incoming
/// records; repair and retention finish before either resulting value is returned.
/// Publication and durable storage must accept this pair together.
public sealed record NativeSyncSessionTransition(NativeSyncJournal Journal, JsonObject Materialization) {
    #region Actions - Sync

    public static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, ReadOnlySpan<byte> input,
        SpaceAccessAuthority? access = null) {
        if (input.Length is 0 or > NativeSyncJournal.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        bool replacing = NativeSyncOperationCodes.Parse(request["operation"]!.GetValue<string>()) switch {
            NativeSyncOperation.Merge => false,
            NativeSyncOperation.Replace => true,
            _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownSyncOperation)
        };
        double now = request["now"]!.GetValue<double>();
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedDate);
        var preferences = request["preferences"]!;
        var local = request["session"]!.AsObject();
        var incoming = request["records"]!.AsArray();
        var next = journal;
        void Apply(NativeSyncOperation operation, JsonObject args) {
            next = next.Apply(Encoding.UTF8.GetBytes(new JsonObject {
                ["version"] = 1,
                ["operation"] = NativeSyncOperationCodes.Name(operation),
                ["preferences"] = preferences.DeepClone(),
                ["arguments"] = args
            }.ToJsonString()));
        }
        void Stage(JsonObject session, string reason) => Apply(NativeSyncOperation.Stage, new JsonObject { ["session"] = session.DeepClone(), ["deletionReason"] = reason, ["now"] = now });
        if (!replacing && local["disposableSeedMarker"] is null) Stage(local, SyncDeletionReasons.Superseded);
        Apply(replacing ? NativeSyncOperation.Replace : NativeSyncOperation.Merge, new JsonObject { ["records"] = incoming.DeepClone() });
        // Only an accepted explicit Space tombstone authorizes deleting this
        // device's profile. Missing records, tab deletion and retention do not.
        local = local.DeepClone().AsObject();
        var pendingIds = (local["spaceDeletions"] as JsonArray ?? new())
            .Select(n => NativeSessionAuthority.Id(n!["spaceID"])).ToHashSet();
        foreach (var record in next.Records.Where(r => r!["id"]?["kind"]?.GetValue<string>() == SyncRecordKinds.Space
            && r["tombstone"]?["reason"]?.GetValue<string>() == SyncDeletionReasons.ExplicitDelete)) {
            var id = NativeSessionAuthority.Id(record!["id"]!["value"]);
            var space = local["spaces"]!.AsArray().FirstOrDefault(s => NativeSessionAuthority.Id(s!["id"]) == id);
            if (space is null || !pendingIds.Add(id)) continue;
            var intents = local["spaceDeletions"] as JsonArray;
            if (intents is null) local["spaceDeletions"] = intents = new JsonArray();
            intents.Add((JsonNode)new JsonObject {
                ["spaceID"] = space["id"]!.DeepClone(),
                ["profileID"] = space["profile"]!["id"]!.DeepClone(),
                ["operationID"] = Guid.NewGuid().ToString("D")
            });
        }
        var raw = replacing && incoming.Count == 0
            ? new JsonObject { ["spaces"] = new JsonArray() }
            : NativeSyncMaterializer.Materialize(local, preferences,
                NativeSyncEvaluator.Reconcile(next.Records).Select(n => n!.AsObject()).ToArray(), now, access);
        var repaired = NativeSessionMaintenance.Repair(raw, now, request["emptySpace"] as JsonObject);
        var retained = NativeSessionMaintenance.Retain(repaired["session"]!.AsObject(), now);
        bool removed = retained["changed"]!.GetValue<bool>();
        repaired["session"] = retained["session"]!.DeepClone();
        // Cleanup already authorized on this device must survive remote deletion,
        // replacement and retention until its local adapters acknowledge it.
        if (local["spaceDeletions"] is JsonArray pending && pending.Count > 0) {
            var result = repaired["session"]!.AsObject();
            result["spaceDeletions"] = pending.DeepClone();
            var spaces = result["spaces"]!.AsArray();
            foreach (var intent in pending) {
                var id = NativeSessionAuthority.Id(intent!["spaceID"]);
                var original = local["spaces"]!.AsArray().Single(s => NativeSessionAuthority.Id(s!["id"]) == id)!;
                var existing = spaces.FirstOrDefault(s => NativeSessionAuthority.Id(s!["id"]) == id);
                if (existing is not null) spaces[spaces.IndexOf(existing)] = original.DeepClone();
                else spaces.Add(original.DeepClone());
            }
        }
        if (!replacing || removed) Stage(repaired["session"]!.AsObject(), removed ? SyncDeletionReasons.Retention : SyncDeletionReasons.Superseded);
        return new(next, repaired);
    }

    #endregion
}
