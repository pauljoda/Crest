using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Variables

    private const int MaximumUrlHostLength = 1_024;

    #endregion

    #region Actions - Origins

    /// Null when the operation is not an external scheme, link or local-file
    /// policy. URLs arrive as the facts the platform's own parser reported
    /// (scheme, host, user and path presence), so both engines judge the same
    /// parse. A caller that gets no answer refuses the URL.
    private static JsonObject? EvaluateOrigins(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.ExternalUrl:
                Protocol.Members(request, "version", "operation", "scheme", "host");
                return new() {
                    ["accepted"] = ExternalUrlPolicy.AcceptsWebLink(Protocol.OptionalText(request, "scheme", ExternalSchemePolicy.MaximumSchemeLength),
                        Protocol.OptionalText(request, "host", MaximumUrlHostLength))
                };
            case PolicyOperation.ExternalLocalDocument:
                Protocol.Members(request, "version", "operation", "isFile", "hasUser", "hasPath", "host");
                return new() {
                    ["accepted"] = ExternalUrlPolicy.AcceptsLocalDocument(new(request.GetProperty("isFile").GetBoolean(),
                        request.GetProperty("hasUser").GetBoolean(), request.GetProperty("hasPath").GetBoolean(),
                        Protocol.OptionalText(request, "host", MaximumUrlHostLength)))
                };
            case PolicyOperation.ExternalScheme:
                Protocol.Members(request, "version", "operation", "scheme", "appInitiated");
                return new() {
                    ["disposition"] = ExternalSchemePolicy.Disposition(Protocol.OptionalText(request, "scheme", ExternalSchemePolicy.MaximumSchemeLength),
                        request.GetProperty("appInitiated").GetBoolean()) switch {
                            ExternalSchemeDisposition.Engine => "engine",
                            ExternalSchemeDisposition.HandOff => "handOff",
                            _ => "blocked"
                        }
                };
            case PolicyOperation.ExternalConsent:
                Protocol.Members(request, "version", "operation", "decision");
                return new() {
                    ["consent"] = ExternalSchemePolicy.Consent(Decision(request)) switch {
                        ExternalSchemeConsent.Open => "open",
                        ExternalSchemeConsent.Prompt => "prompt",
                        _ => "block"
                    }
                };
            default:
                return null;
        }
    }

    #endregion
}
