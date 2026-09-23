using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.ExternalNavigationPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Origins

    /// Null when the operation is not an external scheme, link or local-file
    /// policy. A caller that gets no answer refuses the URL.
    private static JsonObject? EvaluateOrigins(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.ExternalUrl => AcceptWebLink(Requests.WebLink.Decode(request)),
        PolicyOperation.ExternalLocalDocument => ExternalNavigationCodes.AcceptedAnswer(
            ExternalUrlPolicy.AcceptsLocalDocument(Requests.LocalDocument.Decode(request).Facts)),
        PolicyOperation.ExternalScheme => SchemeDisposition(Requests.Scheme.Decode(request)),
        PolicyOperation.ExternalConsent => ExternalNavigationCodes.ConsentAnswer(
            ExternalSchemePolicy.Consent(SitePermissionPolicyRequests.SavedDecision.Decode(request).Decision)),
        _ => null
    };

    private static JsonObject AcceptWebLink(Requests.WebLink request) =>
        ExternalNavigationCodes.AcceptedAnswer(ExternalUrlPolicy.AcceptsWebLink(request.Scheme, request.Host));

    private static JsonObject SchemeDisposition(Requests.Scheme request) => ExternalNavigationCodes.DispositionAnswer(
        ExternalSchemePolicy.Disposition(request.Name, request.AppInitiated));

    #endregion
}
