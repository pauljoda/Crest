using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Prepares the session and journal together. Local edits stage before incoming
/// records; repair and retention finish before either resulting value is returned.
/// Publication and durable storage must accept this pair together.
public sealed record NativeSyncSessionTransition(NativeSyncJournal Journal, JsonObject Materialization) {
    #region Actions - Sync

    /// The journal and repaired session that merging `incoming`, records in the
    /// journal's form, into `local`, a whole session in the stored format, or
    /// replacing it with them, make at `now` in seconds since 2001 under the
    /// journal's sync categories. A merge first stages `local`, deleting each
    /// record the edits it covers removed for the reason `removals` names for
    /// it, else as superseded. `emptySpace` is the Space a session left with
    /// none takes, and `ids` gives repaired records new identities.
    internal static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, JsonObject local, JsonArray incoming,
        bool replacing, double now, JsonObject? emptySpace, SpaceAccessAuthority? access, IIdSource? ids,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedDate);
        var preferences = journal.Preferences;
        var next = journal;
        if (!replacing && local["disposableSeedMarker"] is null)
            next = next.Stage(local.DeepClone().AsObject(), SyncDeletionReason.Superseded, now, removals);
        next = replacing ? next.Replace(incoming) : next.Merge(incoming);
        // Only an accepted explicit Space tombstone authorizes deleting this
        // device's profile. Missing records, tab deletion and retention do not.
        local = local.DeepClone().AsObject();
        var pendingIds = (local["spaceDeletions"] as JsonArray ?? new())
            .Select(n => NativeSessionAuthority.Id(n!["spaceID"])).ToHashSet();
        foreach (var record in next.Records.Where(r => r!["id"]?["kind"]?.GetValue<string>() == SyncRecordKind.Space.Name
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
        if (!replacing || removed)
            next = next.Stage(repaired["session"]!.DeepClone().AsObject(), removed ? SyncDeletionReason.Retention : SyncDeletionReason.Superseded,
                now);
        return new(next, repaired);
    }

    #endregion
}
