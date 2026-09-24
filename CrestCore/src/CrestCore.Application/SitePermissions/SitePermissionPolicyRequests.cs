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
            return new(SitePermissionDocument.DecodeOrigin(Element(request, "origin")));
        }
    }

    public sealed record NotificationRequest(SitePermissionDecision Decision, bool HasUserActivation) {
        public static NotificationRequest Decode(JsonElement request) {
            Members(request, "decision", "hasUserActivation");
            return new(SitePermissionDocument.DecodeDecision(request, "decision"), Flag(request, "hasUserActivation"));
        }
    }

    public sealed record PopupNotice(BlockedPopupPageState State, BlockedPopupEvent Event, string? DocumentIdentifier,
        SiteOrigin? Origin) {
        public static PopupNotice Decode(JsonElement request) {
            Members(request, "state", "event", "documentIdentifier", "origin");
            var state = PopupState(Element(request, "state"));
            var popupEvent = BlockedPopupEvent.Named(Protocol.Text(request, "event", 64))
                ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPopupEvent);
            var document = Protocol.OptionalText(request, "documentIdentifier", BlockedPopupPageState.MaximumDocumentIdentifierLength);
            return new(state, popupEvent, document, SitePermissionDocument.DecodeOptionalOrigin(request, "origin"));
        }

        /// A page's popup notice as the native store keeps it. A status and an
        /// origin come together or not at all.
        private static BlockedPopupPageState PopupState(JsonElement value) {
            Protocol.Members(value, "status", "origin", "documentIdentifier", "indicationRevision");
            var status = Protocol.OptionalText(value, "status", 64) is { } name
                ? BlockedPopupStatus.Named(name) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidStatus)
                : null;
            var origin = SitePermissionDocument.DecodeOptionalOrigin(value, "origin");
            if ((status is null) != (origin is null)) throw new BrowserRuleException(BrowserRuleCodes.InvalidBlockedPopup);
            return new(status, origin,
                Protocol.OptionalText(value, "documentIdentifier", BlockedPopupPageState.MaximumDocumentIdentifierLength),
                value.GetProperty("indicationRevision").GetInt32());
        }
    }

    #endregion
}
