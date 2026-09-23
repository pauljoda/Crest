using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.SitePermissionPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Site permissions

    /// Null when the operation is not a site-permission policy. The saved
    /// choices themselves live in the permission ledger; these operations
    /// answer what a decision, an origin or a page's popup state means.
    private static JsonObject? EvaluateSitePermissions(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.GeolocationOrigin or PolicyOperation.NotificationsOrigin => SitePermissionCodes.OriginAnswer(
            SecureOriginPolicy.Allows(Requests.SecureOrigin.Decode(request).Origin)),
        PolicyOperation.NotificationsPermissionRequest => NotificationRequest(Requests.NotificationRequest.Decode(request)),
        PolicyOperation.PopupsAutomatic => SitePermissionCodes.PopupsAnswer(
            BlockedPopupNoticePolicy.AllowsAutomaticPopups(Requests.SavedDecision.Decode(request).Decision)),
        PolicyOperation.PopupsNotice => PopupNotice(Requests.PopupNotice.Decode(request)),
        _ => null
    };

    private static JsonObject NotificationRequest(Requests.NotificationRequest request) => SitePermissionCodes.NotificationAnswer(
        HostedNotificationRequestPolicy.Action(request.Decision, request.HasUserActivation));

    private static JsonObject PopupNotice(Requests.PopupNotice request) => SitePermissionCodes.NoticeAnswer(
        BlockedPopupNoticePolicy.Apply(request.State, request.Event, request.DocumentIdentifier, request.Origin), request.State);

    #endregion
}
