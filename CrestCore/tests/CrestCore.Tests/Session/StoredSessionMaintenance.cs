using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Tests.Session;

/// Session repair and sync materialization over the stored session's JSON,
/// as the tests' fixtures hold sessions.
internal static class StoredSessionMaintenance {
    #region Actions - Session maintenance

    /// The repaired session and positional asset references: `{"session", "assets"}`.
    internal static JsonObject Repair(JsonObject source, double now, JsonObject? emptySpace = null, IIdSource? ids = null) {
        var repaired = NativeSessionMaintenance.Repair(StoredSessionCodec.DecodeSession(source), StoredSessionCodec.Date(now),
            emptySpace is null ? null : StoredSessionCodec.DecodeSpace(emptySpace), ids ?? new SystemIdSource(), out var origins);
        return NativeSessionMaintenance.Answer(repaired, origins);
    }

    /// `session` with the shared `records` applied, as stored JSON.
    internal static JsonObject Materialize(JsonObject session, JsonNode preferences, IReadOnlyList<JsonObject> records, double now,
        SpaceAccessAuthority? access = null) => StoredSessionCodec.Encode(NativeSyncMaterializer.Materialize(
            StoredSessionCodec.DecodeSession(session), NativeSyncProjection.Preferences(preferences),
            records.Select(SyncSessionRecord.Read).ToArray(), StoredSessionCodec.Date(now), access));

    #endregion
}
