using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the credential and passkey policy operations. They carry
/// identities and metadata only: form messages arrive without their username
/// or password values, and the save plan receives the platform's yes-or-no
/// comparison instead of any stored secret.
internal static class CredentialPolicyRequests {
    #region Actions - Decoding

    public sealed record Capture(CredentialFormFacts Facts, CredentialUsernameHint? Hint, CredentialPendingCandidate? Pending,
        double Now) {
        public static Capture Decode(JsonElement request) {
            Members(request, "event", "frameOrigin", "topLevelOrigin", "isMainFrame", "hasFormID", "hasUsername",
                "hasPassword", "passwordKind", "hasVisiblePasswordField", "hasFillTarget", "now", "usernameHint",
                "pendingCandidate");
            var facts = new CredentialFormFacts(CredentialCodes.ParseEvent(Protocol.Text(request, "event")),
                CredentialCodes.Origin(request, "frameOrigin"), CredentialCodes.Origin(request, "topLevelOrigin"),
                Flag(request, "isMainFrame"), Flag(request, "hasFormID"), Flag(request, "hasUsername"),
                Flag(request, "hasPassword"),
                Optional(request, "passwordKind") is { } kind ? CredentialCodes.ParseKind(kind.GetString()) : null,
                OptionalFlag(request, "hasVisiblePasswordField"), Flag(request, "hasFillTarget"));
            CredentialUsernameHint? hint = null;
            if (Optional(request, "usernameHint") is { } storedHint) {
                Protocol.Members(storedHint, "origin", "topLevelOrigin", "capturedAt");
                hint = new(CredentialCodes.Origin(storedHint, "origin"), CredentialCodes.Origin(storedHint, "topLevelOrigin"),
                    Number(storedHint, "capturedAt"));
            }
            CredentialPendingCandidate? pending = null;
            if (Optional(request, "pendingCandidate") is { } candidate) {
                Protocol.Members(candidate, "origin", "submittedAt");
                pending = new(CredentialCodes.Origin(candidate, "origin"), Number(candidate, "submittedAt"));
            }
            return new(facts, hint, pending, Number(request, "now"));
        }
    }

    public sealed record Fill(CredentialFillSource Source, CredentialPasswordKind Kind) {
        public static Fill Decode(JsonElement request) {
            Members(request, "passwordKind", "source");
            var source = CredentialCodes.ParseSource(Protocol.Text(request, "source"));
            return new(source, CredentialCodes.ParseKind(Protocol.Text(request, "passwordKind")));
        }
    }

    public sealed record SaveValidity(CredentialOrigin Origin, CredentialOrigin TopLevelOrigin, double SubmittedAt, double Now) {
        public static SaveValidity Decode(JsonElement request) {
            Members(request, "origin", "topLevelOrigin", "submittedAt", "now");
            var origin = CredentialCodes.Origin(request, "origin");
            var topLevel = CredentialCodes.Origin(request, "topLevelOrigin");
            double submittedAt = Number(request, "submittedAt");
            return new(origin, topLevel, submittedAt, Number(request, "now"));
        }
    }

    public sealed record MostRecent(IReadOnlyList<CredentialRecord> Records) {
        public static MostRecent Decode(JsonElement request) {
            Members(request, "records");
            return new(CredentialRecords(request, includesUsername: false));
        }
    }

    public sealed record SaveMatch(string Username, IReadOnlyList<CredentialRecord> Records) {
        public static SaveMatch Decode(JsonElement request) {
            Members(request, "username", "records");
            var username = Protocol.Text(request, "username", CredentialCodes.MaximumUsernameLength);
            return new(username, CredentialRecords(request, includesUsername: true));
        }
    }

    public sealed record SavePlan(Guid? MatchId, CredentialStoredComparison? Stored) {
        public static SavePlan Decode(JsonElement request) {
            Members(request, "matchID", "stored");
            CredentialStoredComparison? stored = null;
            if (Optional(request, "stored") is { } comparison) {
                Protocol.Members(comparison, "id", "passwordMatches");
                stored = new(Protocol.Id(comparison, "id"), Flag(comparison, "passwordMatches"));
            }
            return new(Protocol.OptionalId(request, "matchID"), stored);
        }
    }

    public sealed record PasswordRecipe(int? Length) {
        public static PasswordRecipe Decode(JsonElement request) {
            Members(request, "length");
            return new(Optional(request, "length")?.GetInt32());
        }
    }

    public sealed record SystemWriteThrough(bool IsMobilePlatform, bool SupportsSystemApi, bool HasManagedBrowserCapability,
        bool IsLaunchIsolated) {
        public static SystemWriteThrough Decode(JsonElement request) {
            Members(request, "isMobilePlatform", "supportsSystemAPI", "hasManagedBrowserCapability", "isLaunchIsolated");
            bool mobile = Flag(request, "isMobilePlatform"), supports = Flag(request, "supportsSystemAPI"),
                managed = Flag(request, "hasManagedBrowserCapability");
            return new(mobile, supports, managed, Flag(request, "isLaunchIsolated"));
        }
    }

    public sealed record SystemWriteThroughOffer(bool OffersSaveToSystemPasswords,
        SystemPasswordWriteThroughAvailability Availability, bool IsPrivateBrowsing) {
        public static SystemWriteThroughOffer Decode(JsonElement request) {
            Members(request, "offersSaveToSystemPasswords", "availability", "isPrivateBrowsing");
            bool offers = Flag(request, "offersSaveToSystemPasswords");
            var availability = CredentialCodes.ParseAvailability(Protocol.Text(request, "availability"));
            return new(offers, availability, Flag(request, "isPrivateBrowsing"));
        }
    }

    public sealed record PasskeyAccess(bool HasManagedCapability, PasskeyDeviceConfiguration DeviceConfiguration,
        PasskeyAuthorizationState AuthorizationState) {
        public static PasskeyAccess Decode(JsonElement request) {
            Members(request, "hasManagedCapability", "deviceConfiguration", "authorizationState");
            bool managed = Flag(request, "hasManagedCapability");
            var configuration = CredentialCodes.ParseConfiguration(Protocol.Text(request, "deviceConfiguration"));
            return new(managed, configuration, CredentialCodes.ParseAuthorization(Protocol.Text(request, "authorizationState")));
        }
    }

    private static CredentialRecord[] CredentialRecords(JsonElement request, bool includesUsername) {
        var records = Element(request, "records");
        if (records.ValueKind != JsonValueKind.Array) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
        if (records.GetArrayLength() > CredentialRecencyPolicy.MaximumRecords)
            throw new BrowserRuleException(BrowserRuleCodes.CredentialRecordLimit);
        return records.EnumerateArray().Select(record => CredentialCodes.Record(record, includesUsername)).ToArray();
    }

    #endregion
}
