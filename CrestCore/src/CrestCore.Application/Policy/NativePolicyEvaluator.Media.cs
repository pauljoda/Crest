using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.MediaSessionPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Media sessions

    /// Null when the operation is not a media-session policy. The native store
    /// applies the decision to its own state.
    private static JsonObject? EvaluateMedia(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.MediaSessionEvent => DecideMediaSessionEvent(Requests.SessionEvent.Decode(request)),
        PolicyOperation.MediaArbitrate => MediaSessionCodes.ArbitrationAnswer(
            MediaSessionPolicy.Arbitrate(Requests.Arbitration.Decode(request).Sessions)),
        _ => null
    };

    private static JsonObject DecideMediaSessionEvent(Requests.SessionEvent request) => MediaSessionCodes.DecisionAnswer(
        MediaSessionPolicy.Decide(request.Event, request.Identity, request.RetainedIdentities, request.NextOrdinal));

    #endregion
}
