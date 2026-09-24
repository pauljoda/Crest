using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the Quick Window policy operations.
internal static class QuickWindowPolicyRequests {
    #region Actions - Decoding

    public sealed record Dismissal(bool WasArchived, bool WasPromoted, bool HasPage) {
        public static Dismissal Decode(JsonElement request) {
            Members(request, "wasArchived", "wasPromoted", "hasPage");
            bool archived = Flag(request, "wasArchived"), promoted = Flag(request, "wasPromoted");
            return new(archived, promoted, Flag(request, "hasPage"));
        }
    }

    public sealed record Retarget(QuickWindowPlacement Current, QuickWindowPlacement Next, string? PageUrl) {
        public static Retarget Decode(JsonElement request) {
            Members(request, "current", "next", "pageURL");
            var current = QuickWindowCodes.Placement(Element(request, "current"));
            var next = QuickWindowCodes.Placement(Element(request, "next"));
            return new(current, next, Protocol.OptionalText(request, "pageURL"));
        }
    }

    #endregion
}
