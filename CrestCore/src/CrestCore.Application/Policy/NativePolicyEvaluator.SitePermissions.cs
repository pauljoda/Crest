using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using Requests = CrestCore.Application.SitePermissionPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Site permissions

    /// Null when the operation is not a site-permission policy. The saved
    /// choices themselves live in the permission ledger, and what a decision
    /// means travels with the decision; these operations answer what an origin,
    /// a notification request or a page's popup state leads to.
    private static JsonObject? EvaluateSitePermissions(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.GeolocationOrigin or PolicyOperation.NotificationsOrigin =>
            new() { ["allowed"] = SecureOriginPolicy.Allows(Requests.SecureOrigin.Decode(request).Origin) },
        PolicyOperation.NotificationsPermissionRequest => NotificationRequest(Requests.NotificationRequest.Decode(request)),
        PolicyOperation.PopupsNotice => PopupNotice(Requests.PopupNotice.Decode(request)),
        _ => null
    };

    private static JsonObject NotificationRequest(Requests.NotificationRequest request) =>
        new() { ["action"] = HostedNotificationRequestAction.For(request.Decision, request.HasUserActivation).Name };

    /// The page's popup notice after an event; `changed` is false when the
    /// event left the state as it was.
    private static JsonObject PopupNotice(Requests.PopupNotice request) {
        var next = request.Event.Apply(request.State, request.DocumentIdentifier, request.Origin);
        var state = next ?? request.State;
        return new() {
            ["changed"] = next is not null,
            ["state"] = new JsonObject {
                ["status"] = state.Status?.Name,
                ["origin"] = state.Origin is { } origin ? SitePermissionDocument.EncodeOrigin(origin) : null,
                ["documentIdentifier"] = state.DocumentIdentifier,
                ["indicationRevision"] = state.IndicationRevision
            }
        };
    }

    #endregion
}
