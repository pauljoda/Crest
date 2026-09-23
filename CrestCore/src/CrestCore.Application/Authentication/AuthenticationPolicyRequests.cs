using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the HTTP authentication policy operations. No username
/// or password crosses: the challenge arrives as its method, proxy flag and
/// failure count, and the prompt's server as host and port.
internal static class AuthenticationPolicyRequests {
    #region Actions - Decoding

    public sealed record Handling(AuthenticationMethod Method, bool IsProxy, int PreviousFailureCount) {
        public static Handling Decode(JsonElement request) {
            Members(request, "method", "isProxy", "previousFailureCount");
            var method = AuthenticationCodes.Method(Protocol.Text(request, "method", 64));
            bool isProxy = Flag(request, "isProxy");
            return new(method, isProxy, Integer(request, "previousFailureCount"));
        }
    }

    /// The host may be empty; the label then falls back to what else is known.
    public sealed record SourceLabel(string Host, int Port, string? Scheme) {
        public static SourceLabel Decode(JsonElement request) {
            Members(request, "host", "port", "scheme");
            var host = AnyText(request, "host", ExternalNavigationCodes.MaximumUrlHostLength);
            int port = Integer(request, "port");
            return new(host, port, Protocol.OptionalText(request, "scheme", ExternalSchemePolicy.MaximumSchemeLength));
        }
    }

    public sealed record FixtureTrust(string? BundleIdentifier, string? ExpectedCertificateSha256, string ActualCertificateSha256) {
        public static FixtureTrust Decode(JsonElement request) {
            Members(request, "bundleIdentifier", "expectedCertificateSHA256", "actualCertificateSHA256");
            var bundle = Protocol.OptionalText(request, "bundleIdentifier", 256);
            var expected = Protocol.OptionalText(request, "expectedCertificateSHA256", 128);
            return new(bundle, expected, Protocol.Text(request, "actualCertificateSHA256", 128));
        }
    }

    #endregion
}
