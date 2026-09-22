using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Authentication

    /// Null when the operation is not an HTTP authentication policy. No
    /// username or password crosses: the challenge arrives as its method,
    /// proxy flag and failure count, and the prompt's server as host and port.
    private static JsonObject? EvaluateAuthentication(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.AuthenticationHandling:
                Protocol.Members(request, "version", "operation", "method", "isProxy", "previousFailureCount");
                var method = Protocol.Text(request, "method", 64) switch {
                    "httpBasic" => AuthenticationMethod.HttpBasic,
                    "httpDigest" => AuthenticationMethod.HttpDigest,
                    "other" => AuthenticationMethod.Other,
                    _ => throw new ProtocolException(ProtocolErrorCodes.InvalidAuthenticationMethod)
                };
                return new() {
                    ["handling"] = AuthenticationPolicy.Handling(method, request.GetProperty("isProxy").GetBoolean(),
                        request.GetProperty("previousFailureCount").GetInt32()) switch {
                            AuthenticationHandling.PromptForCredentials => "promptForCredentials",
                            AuthenticationHandling.PerformDefaultHandling => "performDefaultHandling",
                            _ => "cancel"
                        }
                };
            case PolicyOperation.AuthenticationSourceLabel:
                Protocol.Members(request, "version", "operation", "host", "port", "scheme");
                var host = request.GetProperty("host");
                if (host.ValueKind != JsonValueKind.String || host.GetString() is not { } name || name.Length > MaximumUrlHostLength)
                    throw new ProtocolException(ProtocolErrorCodes.InvalidString);
                return new() {
                    ["label"] = AuthenticationPolicy.SourceLabel(name, request.GetProperty("port").GetInt32(),
                        Protocol.OptionalText(request, "scheme", ExternalSchemePolicy.MaximumSchemeLength))
                };
            case PolicyOperation.AuthenticationFixtureTrust:
                Protocol.Members(request, "version", "operation", "bundleIdentifier", "expectedCertificateSHA256", "actualCertificateSHA256");
                return new() {
                    ["allowed"] = AuthenticationPolicy.TrustsPhysicalValidationServer(
                        Protocol.OptionalText(request, "bundleIdentifier", 256),
                        Protocol.OptionalText(request, "expectedCertificateSHA256", 128),
                        Protocol.Text(request, "actualCertificateSHA256", 128))
                };
            default:
                return null;
        }
    }

    #endregion
}
