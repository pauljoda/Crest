using System.Text.Json;

using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the media-session policy operations. Only ordering and
/// lifecycle facts cross: metadata, artwork and command endpoints stay in the
/// native store.
internal static class MediaSessionPolicyRequests {
    #region Actions - Decoding

    public sealed record SessionEvent(MediaSessionEvent Event, MediaSessionIdentity Identity, int RetainedIdentities,
        ulong NextOrdinal) {
        public static SessionEvent Decode(JsonElement request) {
            Members(request, "event", "identity", "retainedIdentities", "nextOrdinal");
            var sessionEvent = MediaSessionCodes.Event(Element(request, "event"));
            var identity = MediaSessionCodes.Identity(Element(request, "identity"));
            int retained = DeviceCodes.Count(request, "retainedIdentities");
            return new(sessionEvent, identity, retained, DeviceCodes.Unsigned(request, "nextOrdinal"));
        }
    }

    public sealed record Arbitration(IReadOnlyList<MediaSessionEntry> Sessions) {
        public static Arbitration Decode(JsonElement request) {
            Members(request, "sessions");
            return new(MediaSessionCodes.Sessions(request));
        }
    }

    #endregion
}
