using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Prepares the session and journal together. Local edits stage before incoming
/// records; repair and retention finish before either resulting value is returned.
/// Publication and durable storage must accept this pair together.
public sealed record NativeSyncSessionTransition(NativeSyncJournal Journal, JsonObject Materialization) {
    #region Actions - Sync

    /// TRANSITIONAL until slice 8c ports the journal contract tests: the
    /// transition a JSON merge or replace request names, for those tests. The
    /// app takes cloud records through `CloudSyncIntent`.
    internal static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, ReadOnlySpan<byte> input,
        SpaceAccessAuthority? access = null) {
        if (input.Length is 0 or > NativeSyncJournal.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        bool replacing = NativeSyncOperationCodes.Parse(request["operation"]!.GetValue<string>()) switch {
            NativeSyncOperation.Merge => false,
            NativeSyncOperation.Replace => true,
            _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownSyncOperation)
        };
        return Prepare(journal, request["session"]!.AsObject(), request["records"]!.AsArray(), replacing,
            request["now"]!.GetValue<double>(), request["preferences"]!, request["emptySpace"] as JsonObject, access, ids: null);
    }

    /// The journal and repaired session that merging `incoming`, records in the
    /// journal's form, into `local`, a whole session in the stored format, or
    /// replacing it with them, make at `now` in seconds since 2001 under the
    /// sync category `preferences`. A merge first stages `local`, deleting
    /// each record the edits it covers removed for the reason `removals` names
    /// for it, else as superseded. `emptySpace` is the Space a session left
    /// with none takes, and `ids` gives repaired records new identities.
    internal static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, JsonObject local, JsonArray incoming,
        bool replacing, double now, JsonNode preferences, JsonObject? emptySpace, SpaceAccessAuthority? access, IIdSource? ids,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedDate);
        var next = journal;
        void Apply(NativeSyncOperation operation, JsonObject args, IReadOnlyDictionary<string, SyncDeletionReason>? named = null) {
            var request = Encoding.UTF8.GetBytes(new JsonObject {
                ["version"] = 1,
                ["operation"] = NativeSyncOperationCodes.Name(operation),
                ["preferences"] = preferences.DeepClone(),
                ["arguments"] = args
            }.ToJsonString());
            next = named is null ? next.Apply(request) : next.Apply(request, named);
        }
        void Stage(JsonObject session, SyncDeletionReason reason, IReadOnlyDictionary<string, SyncDeletionReason>? named = null) =>
            Apply(NativeSyncOperation.Stage, new JsonObject { ["session"] = session.DeepClone(), ["deletionReason"] = reason.Name, ["now"] = now },
                named);
        if (!replacing && local["disposableSeedMarker"] is null) Stage(local, SyncDeletionReason.Superseded, removals);
        Apply(replacing ? NativeSyncOperation.Replace : NativeSyncOperation.Merge, new JsonObject { ["records"] = incoming.DeepClone() });
        // Only an accepted explicit Space tombstone authorizes deleting this
        // device's profile. Missing records, tab deletion and retention do not.
        local = local.DeepClone().AsObject();
        var pendingIds = (local["spaceDeletions"] as JsonArray ?? new())
            .Select(n => NativeSessionAuthority.Id(n!["spaceID"])).ToHashSet();
        foreach (var record in next.Records.Where(r => r!["id"]?["kind"]?.GetValue<string>() == SyncRecordKinds.Space
            && SyncDeletionReason.Named(r["tombstone"]?["reason"]?.GetValue<string>())?.IsExplicit == true)) {
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
        var repaired = NativeSessionMaintenance.Repair(raw, now, emptySpace, ids);
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
        // The app-wide behavior preferences are device-local. Incoming records
        // and cloud replacement never carry or replace them.
        if (local[StoredSessionCodec.Key.AppPreferences] is { } appPreferences)
            repaired["session"]![StoredSessionCodec.Key.AppPreferences] = appPreferences.DeepClone();
        if (!replacing || removed) Stage(repaired["session"]!.AsObject(), removed ? SyncDeletionReason.Retention : SyncDeletionReason.Superseded);
        return new(next, repaired);
    }

    #endregion
}
