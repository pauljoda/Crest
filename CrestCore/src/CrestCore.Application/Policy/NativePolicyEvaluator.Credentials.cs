using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.CredentialPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Credentials

    /// Null when the operation is not a credential or passkey policy. No
    /// username value or password crosses; see `CredentialPolicyRequests`.
    private static JsonObject? EvaluateCredentials(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.CredentialsCapture => CaptureCredential(Requests.Capture.Decode(request)),
        PolicyOperation.CredentialsFill => OfferFill(Requests.Fill.Decode(request)),
        PolicyOperation.CredentialsSaveValidity => SaveValidity(Requests.SaveValidity.Decode(request)),
        PolicyOperation.CredentialsMostRecent => CredentialCodes.RecordAnswer(
            CredentialRecencyPolicy.MostRecent(Requests.MostRecent.Decode(request).Records)),
        PolicyOperation.CredentialsSaveMatch => MatchSave(Requests.SaveMatch.Decode(request)),
        PolicyOperation.CredentialsSavePlan => PlanSave(Requests.SavePlan.Decode(request)),
        PolicyOperation.CredentialsPasswordRecipe => CredentialCodes.RecipeAnswer(
            StrongPasswordPolicy.Recipe(Requests.PasswordRecipe.Decode(request).Length)),
        PolicyOperation.CredentialsSystemWriteThrough => WriteThrough(Requests.SystemWriteThrough.Decode(request)),
        PolicyOperation.CredentialsSystemWriteThroughOffer => OfferWriteThrough(Requests.SystemWriteThroughOffer.Decode(request)),
        PolicyOperation.PasskeysAccessStatus => PasskeyStatus(Requests.PasskeyAccess.Decode(request)),
        _ => null
    };

    private static JsonObject CaptureCredential(Requests.Capture request) => CredentialCodes.CaptureAnswer(
        CredentialCapturePolicy.Decide(request.Facts, request.Hint, request.Pending, request.Now));

    private static JsonObject OfferFill(Requests.Fill request) =>
        CredentialCodes.AllowedAnswer(CredentialCapturePolicy.Offers(request.Source, request.Kind));

    private static JsonObject SaveValidity(Requests.SaveValidity request) => CredentialCodes.ValidityAnswer(
        CredentialCapturePolicy.SaveValidity(request.Origin, request.TopLevelOrigin, request.SubmittedAt, request.Now));

    private static JsonObject MatchSave(Requests.SaveMatch request) =>
        CredentialCodes.RecordAnswer(CredentialSavePolicy.Match(request.Username, request.Records));

    private static JsonObject PlanSave(Requests.SavePlan request) =>
        CredentialCodes.PlanAnswer(CredentialSavePolicy.Plan(request.MatchId, request.Stored));

    private static JsonObject WriteThrough(Requests.SystemWriteThrough request) => CredentialCodes.AvailabilityAnswer(
        PasskeyAccessPolicy.WriteThroughAvailability(request.IsMobilePlatform, request.SupportsSystemApi,
            request.HasManagedBrowserCapability, request.IsLaunchIsolated));

    private static JsonObject OfferWriteThrough(Requests.SystemWriteThroughOffer request) => CredentialCodes.OfferAnswer(
        PasskeyAccessPolicy.OffersWriteThrough(request.OffersSaveToSystemPasswords, request.Availability, request.IsPrivateBrowsing));

    private static JsonObject PasskeyStatus(Requests.PasskeyAccess request) => CredentialCodes.StatusAnswer(
        PasskeyAccessPolicy.Status(request.HasManagedCapability, request.DeviceConfiguration, request.AuthorizationState));

    #endregion
}
