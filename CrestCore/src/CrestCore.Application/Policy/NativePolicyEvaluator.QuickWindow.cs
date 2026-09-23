using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.QuickWindowPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Quick Window

    /// Null when the operation is not a Quick Window policy.
    private static JsonObject? EvaluateQuickWindow(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.QuickWindowArchiveLifetime => QuickWindowCodes.LifetimeAnswer(
            QuickWindowPolicy.ArchiveLifetime(Requests.ArchiveLifetime.Decode(request).Policy)),
        PolicyOperation.QuickWindowDismissal => QuickWindowDismissal(Requests.Dismissal.Decode(request)),
        PolicyOperation.QuickWindowRetarget => RetargetQuickWindow(Requests.Retarget.Decode(request)),
        _ => null
    };

    private static JsonObject QuickWindowDismissal(Requests.Dismissal request) => QuickWindowCodes.DismissalAnswer(
        QuickWindowPolicy.ArchivesOnDismissal(request.WasArchived, request.WasPromoted, request.HasPage));

    private static JsonObject RetargetQuickWindow(Requests.Retarget request) => QuickWindowCodes.RetargetAnswer(
        QuickWindowPolicy.Retarget(request.Current, request.Next, request.PageUrl));

    #endregion
}
