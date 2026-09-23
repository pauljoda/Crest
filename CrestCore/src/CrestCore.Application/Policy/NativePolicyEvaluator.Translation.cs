using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.TranslationPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Translation

    /// Null when the operation is not a translation policy.
    private static JsonObject? EvaluateTranslation(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.TranslationRule => ResolveTranslationRule(Requests.Rule.Decode(request)),
        PolicyOperation.TranslationMatches => TranslationMatches(Requests.Matches.Decode(request)),
        _ => null
    };

    private static JsonObject ResolveTranslationRule(Requests.Rule request) =>
        Requests.RuleAnswer(request.Rules.Rule(request.SourceId), request.Rules.Target(request.SourceId));

    private static JsonObject TranslationMatches(Requests.Matches request) =>
        Requests.MatchesAnswer(request.Candidates.Select(candidate => LanguageTag.Matches(request.Language, candidate)));

    #endregion
}
