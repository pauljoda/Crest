using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.AuthenticationPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Authentication

    /// Null when the operation is not an HTTP authentication policy.
    private static JsonObject? EvaluateAuthentication(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.AuthenticationHandling => HandleAuthentication(Requests.Handling.Decode(request)),
        PolicyOperation.AuthenticationSourceLabel => AuthenticationLabel(Requests.SourceLabel.Decode(request)),
        PolicyOperation.AuthenticationFixtureTrust => FixtureTrust(Requests.FixtureTrust.Decode(request)),
        _ => null
    };

    private static JsonObject HandleAuthentication(Requests.Handling request) => AuthenticationCodes.HandlingAnswer(
        AuthenticationPolicy.Handling(request.Method, request.IsProxy, request.PreviousFailureCount));

    private static JsonObject AuthenticationLabel(Requests.SourceLabel request) => AuthenticationCodes.LabelAnswer(
        AuthenticationPolicy.SourceLabel(request.Host, request.Port, request.Scheme));

    private static JsonObject FixtureTrust(Requests.FixtureTrust request) => AuthenticationCodes.TrustAnswer(
        AuthenticationPolicy.TrustsPhysicalValidationServer(request.BundleIdentifier, request.ExpectedCertificateSha256,
            request.ActualCertificateSha256));

    #endregion
}
