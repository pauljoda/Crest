using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The legacy checkpoint answer preserves opaque device preferences and pending
/// deletion checkpoints at the boundary. Typed convergence never parses this answer.
internal static class NativeSyncCheckpointCodec {
    #region Actions - Encoding

    internal static JsonObject Encode(SessionState sessionState, IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins,
        JsonObject? legacyLocal) {
        var answer = NativeSessionMaintenance.Answer(sessionState, origins);
        if (legacyLocal is null) return answer;
        var session = answer["session"]!.AsObject();
        if (legacyLocal[StoredSessionCodec.Key.AppPreferences] is { } preferences)
            session[StoredSessionCodec.Key.AppPreferences] = preferences.DeepClone();
        foreach (var intent in (session["spaceDeletions"] as JsonArray ?? [])) {
            var spaceId = StoredSessionCodec.Identity(intent!["spaceID"]);
            var original = legacyLocal["spaces"]!.AsArray().Single(space => StoredSessionCodec.Identity(space!["id"]) == spaceId)!;
            var prior = (legacyLocal["spaceDeletions"] as JsonArray ?? []).FirstOrDefault(deletion =>
                StoredSessionCodec.Identity(deletion!["spaceID"]) == spaceId);
            if (prior is not null) {
                foreach (var field in prior.AsObject()) {
                    if (field.Key is StoredSessionCodec.Key.ErasedProfileIds or StoredSessionCodec.Key.SuccessorSpaceId) continue;
                    intent[field.Key] = field.Value?.DeepClone();
                }
            } else {
                intent["spaceID"] = original["id"]!.DeepClone();
                intent["profileID"] = original["profile"]!["id"]!.DeepClone();
            }
            var spaces = session["spaces"]!.AsArray();
            int index = spaces.ToList().FindIndex(space => StoredSessionCodec.Identity(space!["id"]) == spaceId);
            var kept = original.DeepClone();
            // A handover may have moved the primary's pins. Keep the final
            // tab list so the asset positions and owners still agree.
            if (sessionState.PendingDeletion(spaceId)?.SuccessorId is not null && original[StoredSessionCodec.Key.Tabs] is JsonArray tabs
                && tabs.Count != sessionState.Spaces[index].Tabs.Count)
                kept[StoredSessionCodec.Key.Tabs] = spaces[index]![StoredSessionCodec.Key.Tabs]?.DeepClone();
            spaces[index] = kept;
        }
        return answer;
    }

    #endregion
}
