using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the external scheme, link and local-file policy
/// operations. URLs arrive as the facts the platform's own parser reported
/// (scheme, host, user and path presence), so both engines judge the same parse.
internal static class ExternalNavigationPolicyRequests {
    #region Actions - Decoding

    public sealed record WebLink(string? Scheme, string? Host) {
        public static WebLink Decode(JsonElement request) {
            Members(request, "scheme", "host");
            var scheme = Protocol.OptionalText(request, "scheme", ExternalSchemePolicy.MaximumSchemeLength);
            return new(scheme, Protocol.OptionalText(request, "host", ExternalNavigationCodes.MaximumUrlHostLength));
        }
    }

    public sealed record LocalDocument(LocalDocumentFacts Facts) {
        public static LocalDocument Decode(JsonElement request) {
            Members(request, "isFile", "hasUser", "hasPath", "host");
            bool isFile = Flag(request, "isFile"), hasUser = Flag(request, "hasUser"), hasPath = Flag(request, "hasPath");
            return new(new LocalDocumentFacts(isFile, hasUser, hasPath,
                Protocol.OptionalText(request, "host", ExternalNavigationCodes.MaximumUrlHostLength)));
        }
    }

    public sealed record Scheme(string? Name, bool AppInitiated) {
        public static Scheme Decode(JsonElement request) {
            Members(request, "scheme", "appInitiated");
            var scheme = Protocol.OptionalText(request, "scheme", ExternalSchemePolicy.MaximumSchemeLength);
            return new(scheme, Flag(request, "appInitiated"));
        }
    }

    #endregion
}
