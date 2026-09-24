using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.PresentationPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Presentation

    /// Null when the operation is not a page presentation or branding policy.
    private static JsonObject? EvaluatePresentation(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.PagePresentation:
                return PresentPage(Requests.Page.Decode(request));
            case PolicyOperation.BrandingNormalize:
                return PresentationCodes.BrandingAnswer(StoredSessionCodec.Encode(
                    SpaceBrandingPolicy.Normalize(StoredSessionCodec.DecodeBranding(Requests.Branding.Decode(request).Document))));
            default:
                return null;
        }
    }

    private static JsonObject PresentPage(Requests.Page request) => PresentationCodes.PresentationAnswer(
        PagePresentationPolicy.Resolve(request.Selection, request.HasActivePage, request.HasNavigationFailure,
            request.HasProcessFailure, request.UnloadedBehavior));

    #endregion
}
