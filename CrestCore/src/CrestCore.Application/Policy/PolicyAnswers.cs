using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Answer shapes several policy families share.
internal static class PolicyAnswers {
    #region Actions - Encoding

    /// An editor's rule violation, answered as `{"error":code}` so the editor
    /// can explain the specific rule instead of failing the call.
    public static JsonObject Error(BrowserRuleException error) => new() { ["error"] = error.Code };

    #endregion
}
