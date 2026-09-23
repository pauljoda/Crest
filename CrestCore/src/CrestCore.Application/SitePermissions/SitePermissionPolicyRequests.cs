using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the site-permission policy operations. The saved
/// choices live in the permission ledger; these carry one decision, origin or
/// page popup state to interpret.
internal static class SitePermissionPolicyRequests {
    #region Actions - Decoding

    public sealed record SecureOrigin(SiteOrigin Origin) {
        public static SecureOrigin Decode(JsonElement request) {
            Members(request, "origin");
            return new(SitePermissionCodes.Origin(request, "origin"));
        }
    }

    public sealed record NotificationRequest(SitePermissionDecision Decision, bool HasUserActivation) {
        public static NotificationRequest Decode(JsonElement request) {
            Members(request, "decision", "hasUserActivation");
            var decision = SitePermissionCodes.Decision(request, "decision");
            return new(decision, Flag(request, "hasUserActivation"));
        }
    }

    /// A saved decision alone, as `popups.automatic` and `external.consent` ask.
    public sealed record SavedDecision(SitePermissionDecision Decision) {
        public static SavedDecision Decode(JsonElement request) {
            Members(request, "decision");
            return new(SitePermissionCodes.Decision(request, "decision"));
        }
    }

    public sealed record PopupNotice(BlockedPopupPageState State, BlockedPopupEvent Event, string? DocumentIdentifier,
        SiteOrigin? Origin) {
        public static PopupNotice Decode(JsonElement request) {
            Members(request, "state", "event", "documentIdentifier", "origin");
            var state = SitePermissionCodes.PopupState(Element(request, "state"));
            var popupEvent = SitePermissionCodes.PopupEvent(Protocol.Text(request, "event", 64));
            var document = Protocol.OptionalText(request, "documentIdentifier", BlockedPopupPageState.MaximumDocumentIdentifierLength);
            return new(state, popupEvent, document, SitePermissionCodes.OptionalOrigin(request, "origin"));
        }
    }

    #endregion
}
