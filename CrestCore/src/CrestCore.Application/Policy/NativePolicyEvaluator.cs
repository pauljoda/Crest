using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// Bounded, deterministic domain calls for existing synchronous native APIs.
/// This path owns no session, queue, engine, I/O, callback, or retained state.
/// Each policy family decodes its typed request, calls the domain and encodes
/// its answer in its own partial file.
public static partial class NativePolicyEvaluator {
    #region Variables

    public const int MaximumInputBytes = 16_384;
    public const int MaximumOutputBytes = 65_536;

    #endregion

    #region Actions - Policy

    public static byte[] Evaluate(ReadOnlySpan<byte> utf8) {
        if (utf8.Length > MaximumInputBytes) throw new ProtocolException(ProtocolErrorCodes.PolicyInputLimit);
        var request = Protocol.Parse(utf8);
        if (request.GetProperty(PolicyFields.Version).GetInt32() != 1) throw new ProtocolException(ProtocolErrorCodes.VersionMismatch);
        var operation = PolicyOperationCodes.Parse(Protocol.Text(request, PolicyFields.Operation));
        var answer = EvaluateDownloads(operation, request)
            ?? EvaluateSearch(operation, request)
            ?? EvaluateTranslation(operation, request)
            ?? EvaluateSitePermissions(operation, request)
            ?? EvaluateOrigins(operation, request)
            ?? EvaluateAuthentication(operation, request)
            ?? EvaluateLinks(operation, request)
            ?? EvaluateQuickWindow(operation, request)
            ?? EvaluatePresentation(operation, request)
            ?? EvaluateSetup(operation, request)
            ?? EvaluateLaunch(operation, request)
            ?? EvaluateMedia(operation, request)
            ?? EvaluateNavigation(operation, request)
            ?? EvaluateTabs(operation, request)
            ?? EvaluateLimits(operation, request)
            ?? throw new ProtocolException(ProtocolErrorCodes.UnknownPolicy);
        return Encode(answer);
    }

    private static byte[] Encode(JsonObject value) => Encoding.UTF8.GetBytes(value.ToJsonString());

    #endregion
}
