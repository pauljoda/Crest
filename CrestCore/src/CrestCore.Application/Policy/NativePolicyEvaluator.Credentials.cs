using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Credentials

    /// Null when the operation is not a credential or passkey policy. These
    /// operations receive identities and metadata only: form messages arrive
    /// without their username or password values, and the save plan receives
    /// the platform's yes-or-no comparison instead of any stored secret.
    private static JsonObject? EvaluateCredentials(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.CredentialsCapture: {
                    Protocol.Members(request, "version", "operation", "event", "frameOrigin", "topLevelOrigin", "isMainFrame",
                        "hasFormID", "hasUsername", "hasPassword", "passwordKind", "hasVisiblePasswordField", "hasFillTarget",
                        "now", "usernameHint", "pendingCandidate");
                    var facts = new CredentialFormFacts(CredentialCodes.ParseEvent(Protocol.Text(request, "event")),
                        CredentialCodes.Origin(request, "frameOrigin"), CredentialCodes.Origin(request, "topLevelOrigin"),
                        request.GetProperty("isMainFrame").GetBoolean(), request.GetProperty("hasFormID").GetBoolean(),
                        request.GetProperty("hasUsername").GetBoolean(), request.GetProperty("hasPassword").GetBoolean(),
                        Optional(request, "passwordKind") is { } kind ? CredentialCodes.ParseKind(kind.GetString()) : null,
                        Optional(request, "hasVisiblePasswordField")?.GetBoolean(),
                        request.GetProperty("hasFillTarget").GetBoolean());
                    CredentialUsernameHint? hint = null;
                    if (Optional(request, "usernameHint") is { } storedHint) {
                        Protocol.Members(storedHint, "origin", "topLevelOrigin", "capturedAt");
                        hint = new(CredentialCodes.Origin(storedHint, "origin"), CredentialCodes.Origin(storedHint, "topLevelOrigin"),
                            storedHint.GetProperty("capturedAt").GetDouble());
                    }
                    CredentialPendingCandidate? pending = null;
                    if (Optional(request, "pendingCandidate") is { } candidate) {
                        Protocol.Members(candidate, "origin", "submittedAt");
                        pending = new(CredentialCodes.Origin(candidate, "origin"), candidate.GetProperty("submittedAt").GetDouble());
                    }
                    var decision = CredentialCapturePolicy.Decide(facts, hint, pending, request.GetProperty("now").GetDouble());
                    return new() {
                        ["action"] = CredentialCodes.Action(decision.Action),
                        ["usernameSource"] = CredentialCodes.Source(decision.UsernameSource),
                        ["clearsUsernameHint"] = decision.ClearsUsernameHint,
                        ["isCrossOriginFrame"] = decision.IsCrossOriginFrame,
                        ["anchorsToField"] = decision.AnchorsToField,
                        ["candidateLifetime"] = CredentialCapturePolicy.CandidateLifetime,
                        ["usernameHintLifetime"] = CredentialCapturePolicy.UsernameHintLifetime
                    };
                }
            case PolicyOperation.CredentialsFill:
                Protocol.Members(request, "version", "operation", "passwordKind", "source");
                return new() {
                    ["allowed"] = CredentialCapturePolicy.Offers(CredentialCodes.ParseSource(Protocol.Text(request, "source")),
                        CredentialCodes.ParseKind(Protocol.Text(request, "passwordKind")))
                };
            case PolicyOperation.CredentialsSaveValidity:
                Protocol.Members(request, "version", "operation", "origin", "topLevelOrigin", "submittedAt", "now");
                return new() {
                    ["verdict"] = CredentialCodes.Validity(CredentialCapturePolicy.SaveValidity(
                        CredentialCodes.Origin(request, "origin"), CredentialCodes.Origin(request, "topLevelOrigin"),
                        request.GetProperty("submittedAt").GetDouble(), request.GetProperty("now").GetDouble()))
                };
            case PolicyOperation.CredentialsMostRecent:
                Protocol.Members(request, "version", "operation", "records");
                return new() { ["id"] = CredentialRecencyPolicy.MostRecent(Records(request, includesUsername: false))?.Id.ToString() };
            case PolicyOperation.CredentialsSaveMatch:
                Protocol.Members(request, "version", "operation", "username", "records");
                return new() {
                    ["id"] = CredentialSavePolicy.Match(Protocol.Text(request, "username", CredentialCodes.MaximumUsernameLength),
                        Records(request, includesUsername: true))?.Id.ToString()
                };
            case PolicyOperation.CredentialsSavePlan: {
                    Protocol.Members(request, "version", "operation", "matchID", "stored");
                    CredentialStoredComparison? stored = null;
                    if (Optional(request, "stored") is { } comparison) {
                        Protocol.Members(comparison, "id", "passwordMatches");
                        stored = new(Protocol.Id(comparison, "id"), comparison.GetProperty("passwordMatches").GetBoolean());
                    }
                    var plan = CredentialSavePolicy.Plan(Protocol.OptionalId(request, "matchID"), stored);
                    return new() {
                        ["plan"] = CredentialCodes.Plan(plan.Kind),
                        ["id"] = plan.Id?.ToString(),
                        ["requiresConfirmation"] = plan.RequiresConfirmation
                    };
                }
            case PolicyOperation.CredentialsPasswordRecipe: {
                    Protocol.Members(request, "version", "operation", "length");
                    var recipe = StrongPasswordPolicy.Recipe(Optional(request, "length")?.GetInt32());
                    return new() {
                        ["length"] = recipe.Length,
                        ["groups"] = new JsonArray(recipe.Groups.Select(group => (JsonNode?)JsonValue.Create(group)).ToArray())
                    };
                }
            case PolicyOperation.CredentialsSystemWriteThrough:
                Protocol.Members(request, "version", "operation", "isMobilePlatform", "supportsSystemAPI",
                    "hasManagedBrowserCapability", "isLaunchIsolated");
                return new() {
                    ["availability"] = CredentialCodes.Availability(PasskeyAccessPolicy.WriteThroughAvailability(
                        request.GetProperty("isMobilePlatform").GetBoolean(), request.GetProperty("supportsSystemAPI").GetBoolean(),
                        request.GetProperty("hasManagedBrowserCapability").GetBoolean(),
                        request.GetProperty("isLaunchIsolated").GetBoolean()))
                };
            case PolicyOperation.CredentialsSystemWriteThroughOffer:
                Protocol.Members(request, "version", "operation", "offersSaveToSystemPasswords", "availability", "isPrivateBrowsing");
                return new() {
                    ["offers"] = PasskeyAccessPolicy.OffersWriteThrough(request.GetProperty("offersSaveToSystemPasswords").GetBoolean(),
                        CredentialCodes.ParseAvailability(Protocol.Text(request, "availability")),
                        request.GetProperty("isPrivateBrowsing").GetBoolean())
                };
            case PolicyOperation.PasskeysAccessStatus:
                Protocol.Members(request, "version", "operation", "hasManagedCapability", "deviceConfiguration", "authorizationState");
                return new() {
                    ["status"] = CredentialCodes.Status(PasskeyAccessPolicy.Status(request.GetProperty("hasManagedCapability").GetBoolean(),
                        CredentialCodes.ParseConfiguration(Protocol.Text(request, "deviceConfiguration")),
                        CredentialCodes.ParseAuthorization(Protocol.Text(request, "authorizationState"))))
                };
            default:
                return null;
        }
    }

    private static CredentialRecord[] Records(JsonElement request, bool includesUsername) {
        var records = request.GetProperty("records");
        if (records.ValueKind != JsonValueKind.Array) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
        if (records.GetArrayLength() > CredentialRecencyPolicy.MaximumRecords)
            throw new BrowserRuleException(BrowserRuleCodes.CredentialRecordLimit);
        return records.EnumerateArray().Select(record => CredentialCodes.Record(record, includesUsername)).ToArray();
    }

    #endregion
}
