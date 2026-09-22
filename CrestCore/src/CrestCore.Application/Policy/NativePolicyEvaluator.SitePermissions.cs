using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Site permissions

    /// Null when the operation is not a site-permission policy. The saved
    /// choices themselves live in the permission ledger; these operations
    /// answer what a decision, an origin or a page's popup state means.
    private static JsonObject? EvaluateSitePermissions(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.GeolocationOrigin or PolicyOperation.NotificationsOrigin:
                Protocol.Members(request, "version", "operation", "origin");
                return new() { ["allowed"] = SecureOriginPolicy.Allows(SitePermissionCodes.Origin(request, "origin")) };
            case PolicyOperation.NotificationsPermissionRequest:
                Protocol.Members(request, "version", "operation", "decision", "hasUserActivation");
                return new() {
                    ["action"] = HostedNotificationRequestPolicy.Action(Decision(request),
                        request.GetProperty("hasUserActivation").GetBoolean()) switch {
                            HostedNotificationRequestAction.RespondDefault => "respondDefault",
                            HostedNotificationRequestAction.ResolveSystemAuthorization => "resolveSystemAuthorization",
                            HostedNotificationRequestAction.PromptForSitePermission => "promptForSitePermission",
                            _ => "respondDenied"
                        }
                };
            case PolicyOperation.PopupsAutomatic:
                Protocol.Members(request, "version", "operation", "decision");
                return new() { ["allows"] = BlockedPopupNoticePolicy.AllowsAutomaticPopups(Decision(request)) };
            case PolicyOperation.PopupsNotice:
                Protocol.Members(request, "version", "operation", "state", "event", "documentIdentifier", "origin");
                var state = PopupState(request.GetProperty("state"));
                var next = BlockedPopupNoticePolicy.Apply(state, PopupEvent(Protocol.Text(request, "event", 64)),
                    Protocol.OptionalText(request, "documentIdentifier", BlockedPopupPageState.MaximumDocumentIdentifierLength),
                    SitePermissionCodes.OptionalOrigin(request, "origin"));
                return new() { ["changed"] = next is not null, ["state"] = PopupState(next ?? state) };
            default:
                return null;
        }
    }

    private static SitePermissionDecision Decision(JsonElement request) =>
        SitePermissionCodes.ParseDecision(Protocol.Text(request, "decision", 64));

    private static BlockedPopupEvent PopupEvent(string value) => value switch {
        "blocked" => BlockedPopupEvent.Blocked,
        "permission_allowed" => BlockedPopupEvent.PermissionAllowed,
        "permission_blocked_again" => BlockedPopupEvent.PermissionBlockedAgain,
        "navigation" => BlockedPopupEvent.Navigation,
        "popup_allowed" => BlockedPopupEvent.PopupAllowed,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPopupEvent)
    };

    private static BlockedPopupPageState PopupState(JsonElement value) {
        Protocol.Members(value, "status", "origin", "documentIdentifier", "indicationRevision");
        BlockedPopupStatus? status = Protocol.OptionalText(value, "status", 64) switch {
            null => null,
            "blocked" => BlockedPopupStatus.Blocked,
            "allowedAwaitingRetry" => BlockedPopupStatus.AllowedAwaitingRetry,
            _ => throw new ProtocolException(ProtocolErrorCodes.InvalidStatus)
        };
        var origin = SitePermissionCodes.OptionalOrigin(value, "origin");
        if ((status is null) != (origin is null)) throw new BrowserRuleException(BrowserRuleCodes.InvalidBlockedPopup);
        return new(status, origin,
            Protocol.OptionalText(value, "documentIdentifier", BlockedPopupPageState.MaximumDocumentIdentifierLength),
            value.GetProperty("indicationRevision").GetInt32());
    }

    private static JsonObject PopupState(BlockedPopupPageState state) => new() {
        ["status"] = state.Status switch {
            BlockedPopupStatus.Blocked => "blocked",
            BlockedPopupStatus.AllowedAwaitingRetry => "allowedAwaitingRetry",
            _ => null
        },
        ["origin"] = state.Origin is { } origin ? SitePermissionCodes.Origin(origin) : null,
        ["documentIdentifier"] = state.DocumentIdentifier,
        ["indicationRevision"] = state.IndicationRevision
    };

    #endregion
}
