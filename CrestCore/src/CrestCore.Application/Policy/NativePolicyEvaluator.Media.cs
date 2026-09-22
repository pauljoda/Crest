using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Media sessions

    /// Null when the operation is not a media-session policy. Only ordering and
    /// lifecycle facts cross: metadata, artwork and command endpoints stay in
    /// the native store, which applies the decision to its own state.
    private static JsonObject? EvaluateMedia(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.MediaSessionEvent: {
                    Protocol.Members(request, "version", "operation", "event", "identity", "retainedIdentities", "nextOrdinal");
                    var decision = MediaSessionPolicy.Decide(MediaSessionCodes.Event(request.GetProperty("event")),
                        MediaSessionCodes.Identity(request.GetProperty("identity")),
                        DeviceCodes.Count(request, "retainedIdentities"), DeviceCodes.Unsigned(request, "nextOrdinal"));
                    return new() {
                        ["accepted"] = decision.Accepted,
                        ["evictOldest"] = decision.EvictOldest,
                        ["disposition"] = MediaSessionCodes.Disposition(decision.Disposition),
                        ["supersedesTabSiblings"] = decision.SupersedesTabSiblings,
                        ["ordinal"] = decision.Ordinal,
                        ["nextOrdinal"] = decision.NextOrdinal,
                        ["clearsDismissal"] = decision.ClearsDismissal
                    };
                }
            case PolicyOperation.MediaArbitrate: {
                    Protocol.Members(request, "version", "operation", "sessions");
                    var arbitration = MediaSessionPolicy.Arbitrate(MediaSessionCodes.Sessions(request));
                    return new() {
                        ["order"] = new JsonArray(arbitration.Order.Select(index => (JsonNode?)JsonValue.Create(index)).ToArray()),
                        ["nowPlaying"] = arbitration.NowPlaying
                    };
                }
            default:
                return null;
        }
    }

    #endregion
}
