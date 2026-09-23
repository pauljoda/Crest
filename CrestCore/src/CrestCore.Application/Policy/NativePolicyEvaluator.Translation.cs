using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Variables

    private const int MaximumLanguageCandidates = 256;

    #endregion

    #region Actions - Translation

    /// Null when the operation is not a translation policy. Rules travel in
    /// their persisted native shape: `{"sources":{"es":{"targetID":"en","isEnabled":true}}}`.
    /// Rule edits are the session's `preferences.translation_rule` command.
    private static JsonObject? EvaluateTranslation(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.TranslationRule:
                Protocol.Members(request, "version", "operation", "rules", "sourceID");
                var rules = TranslationRules(request.GetProperty("rules"));
                var source = Language(request, "sourceID");
                return new() {
                    ["rule"] = rules.Rule(source) is { } rule ? TranslationRuleValue(rule) : null,
                    ["target"] = rules.Target(source)
                };
            case PolicyOperation.TranslationMatches:
                Protocol.Members(request, "version", "operation", "language", "candidates");
                var language = Language(request, "language");
                var candidates = request.GetProperty("candidates");
                if (candidates.GetArrayLength() > MaximumLanguageCandidates) throw new ProtocolException(ProtocolErrorCodes.LanguageBatchLimit);
                return new() {
                    ["matches"] = new JsonArray(candidates.EnumerateArray().Select(candidate => (JsonNode?)JsonValue.Create(
                        LanguageTag.Matches(language, LanguageValue(candidate)))).ToArray())
                };
            default:
                return null;
        }
    }

    private static AutomaticTranslationRules TranslationRules(JsonElement value) {
        Protocol.Members(value, "sources");
        var sources = value.GetProperty("sources");
        if (sources.ValueKind != JsonValueKind.Object) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
        return AutomaticTranslationRules.Restore(sources.EnumerateObject().Select(member => {
            Protocol.Members(member.Value, "targetID", "isEnabled");
            return KeyValuePair.Create(member.Name,
                new TranslationRule(Language(member.Value, "targetID"), member.Value.GetProperty("isEnabled").GetBoolean()));
        }));
    }

    private static JsonObject TranslationRuleValue(TranslationRule rule) =>
        new() { ["targetID"] = rule.TargetId, ["isEnabled"] = rule.IsEnabled };

    /// A language identifier, which may be empty when nothing was detected.
    private static string Language(JsonElement value, string field) => LanguageValue(value.GetProperty(field));

    private static string LanguageValue(JsonElement value) {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { } text
            || text.Length > AutomaticTranslationRules.MaximumLanguageLength)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return text;
    }

    #endregion
}
