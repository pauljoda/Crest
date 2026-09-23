using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the HTTP authentication policy operations. They match
/// the native challenge models' case names.
internal static class AuthenticationCodes {
    #region Actions - Decoding

    public static AuthenticationMethod Method(string value) => value switch {
        "httpBasic" => AuthenticationMethod.HttpBasic,
        "httpDigest" => AuthenticationMethod.HttpDigest,
        "other" => AuthenticationMethod.Other,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidAuthenticationMethod)
    };

    #endregion

    #region Actions - Encoding

    public static string Handling(AuthenticationHandling handling) => handling switch {
        AuthenticationHandling.PromptForCredentials => "promptForCredentials",
        AuthenticationHandling.PerformDefaultHandling => "performDefaultHandling",
        _ => "cancel"
    };

    public static JsonObject HandlingAnswer(AuthenticationHandling handling) => new() { ["handling"] = Handling(handling) };

    public static JsonObject LabelAnswer(string? label) => new() { ["label"] = label };

    public static JsonObject TrustAnswer(bool allowed) => new() { ["allowed"] = allowed };

    #endregion
}
