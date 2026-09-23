using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests and answers for the translation policy operations. Rules
/// travel in their persisted native shape,
/// `{"sources":{"es":{"targetID":"en","isEnabled":true}}}`, and are validated
/// strictly here; rule edits are the session's `preferences.translation_rule`.
internal static class TranslationPolicyRequests {
    #region Variables

    private const int MaximumLanguageCandidates = 256;
    private const string Sources = "sources";

    #endregion

    #region Actions - Decoding

    public sealed record Rule(AutomaticTranslationRules Rules, string SourceId) {
        public static Rule Decode(JsonElement request) {
            Members(request, "rules", PreferenceCodes.SourceId);
            var rules = TranslationRules(Element(request, "rules"));
            return new(rules, LanguageField(request, PreferenceCodes.SourceId));
        }
    }

    public sealed record Matches(string Language, IReadOnlyList<string> Candidates) {
        public static Matches Decode(JsonElement request) {
            Members(request, "language", "candidates");
            var language = LanguageField(request, "language");
            var candidates = Element(request, "candidates");
            if (candidates.GetArrayLength() > MaximumLanguageCandidates) throw new ProtocolException(ProtocolErrorCodes.LanguageBatchLimit);
            return new(language, candidates.EnumerateArray().Select(LanguageValue).ToArray());
        }
    }

    private static AutomaticTranslationRules TranslationRules(JsonElement value) {
        Protocol.Members(value, Sources);
        var sources = value.GetProperty(Sources);
        if (sources.ValueKind != JsonValueKind.Object) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
        return AutomaticTranslationRules.Restore(sources.EnumerateObject().Select(member => {
            Protocol.Members(member.Value, PreferenceCodes.TargetId, PreferenceCodes.IsEnabled);
            return KeyValuePair.Create(member.Name,
                new TranslationRule(LanguageField(member.Value, PreferenceCodes.TargetId), Flag(member.Value, PreferenceCodes.IsEnabled)));
        }));
    }

    /// A language identifier, which may be empty when nothing was detected.
    private static string LanguageField(JsonElement value, string field) => LanguageValue(value.GetProperty(field));

    private static string LanguageValue(JsonElement value) {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { } text
            || text.Length > AutomaticTranslationRules.MaximumLanguageLength)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return text;
    }

    #endregion

    #region Actions - Encoding

    public static JsonObject RuleAnswer(TranslationRule? rule, string? target) => new() {
        ["rule"] = rule is { } value
            ? new JsonObject { [PreferenceCodes.TargetId] = value.TargetId, [PreferenceCodes.IsEnabled] = value.IsEnabled }
            : null,
        ["target"] = target
    };

    public static JsonObject MatchesAnswer(IEnumerable<bool> matches) => new() {
        ["matches"] = new JsonArray(matches.Select(match => (JsonNode?)JsonValue.Create(match)).ToArray())
    };

    #endregion
}
