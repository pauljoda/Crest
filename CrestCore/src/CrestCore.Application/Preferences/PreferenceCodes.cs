using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire and stored spellings for the app-wide behavior preferences. Values keep
/// the raw values the native settings stored before the core owned them.
internal static class PreferenceCodes {
    #region Variables

    public const string Startup = "startupBehavior";
    public const string OffersTranslation = "offersTranslation";
    public const string AutomaticallyTranslates = "automaticallyTranslates";
    public const string TranslationRules = "translationRules";
    public const string ChecksSpelling = "checksSpelling";
    public const string AutomaticallyEntersPictureInPicture = "automaticallyEntersPictureInPicture";
    public const string SavedTabClose = "savedTabClosePolicy";
    public const string SavedTabFaviconReturnsToSavedUrl = "savedTabFaviconReturnsToSavedURL";
    public const string SplitFocusFollowsMouse = "splitFocusFollowsMouse";
    public const string Record = "preferences";
    public const string PreferenceName = "preference";
    public const string PreferenceValue = "value";
    public const string Legacy = "legacy";
    public const string SourceId = "sourceID";
    public const string TargetId = "targetID";
    public const string IsEnabled = "isEnabled";
    private const string Sources = "sources";

    #endregion

    #region Actions - Decoding

    public static BrowserPreference Preference(JsonNode? value) => Text(value) switch {
        Startup => BrowserPreference.Startup,
        OffersTranslation => BrowserPreference.OffersTranslation,
        AutomaticallyTranslates => BrowserPreference.AutomaticallyTranslates,
        ChecksSpelling => BrowserPreference.ChecksSpelling,
        AutomaticallyEntersPictureInPicture => BrowserPreference.AutomaticallyEntersPictureInPicture,
        SavedTabClose => BrowserPreference.SavedTabClose,
        SavedTabFaviconReturnsToSavedUrl => BrowserPreference.SavedTabFaviconReturnsToSavedUrl,
        SplitFocusFollowsMouse => BrowserPreference.SplitFocusFollowsMouse,
        _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownPreference)
    };

    /// A stored or legacy value this build does not recognise reads as absent.
    public static StartupBehavior? StartupValue(JsonNode? value) => Text(value) switch {
        "showStartPage" => StartupBehavior.ShowStartPage,
        "lastActiveTab" => StartupBehavior.LastActiveTab,
        _ => null
    };

    public static SavedTabClosePolicy? SavedTabCloseValue(JsonNode? value) => Text(value) switch {
        "resumeLastLocation" => SavedTabClosePolicy.ResumeLastLocation,
        "returnToSavedURL" => SavedTabClosePolicy.ReturnToSavedUrl,
        _ => null
    };

    public static bool? Flag(JsonNode? value) =>
        value is JsonValue flag && flag.GetValueKind() is JsonValueKind.True or JsonValueKind.False ? flag.GetValue<bool>() : null;

    /// Rules in their persisted native shape, `{"sources":{"es":{"targetID":"en","isEnabled":true}}}`.
    /// A rule set that no longer validates reads as no rules, which never translates.
    public static AutomaticTranslationRules Rules(JsonNode? value) {
        if (value?[Sources] is not JsonObject sources) return AutomaticTranslationRules.Empty;
        try {
            return AutomaticTranslationRules.Restore(sources.Select(member => KeyValuePair.Create(member.Key,
                new TranslationRule(Text(member.Value?[TargetId]) ?? "", Flag(member.Value?[IsEnabled]) ?? false))));
        } catch (BrowserRuleException) {
            return AutomaticTranslationRules.Empty;
        }
    }

    /// A language identifier, which may be empty when nothing was detected.
    public static string Language(JsonNode? value) =>
        Text(value) is { Length: <= AutomaticTranslationRules.MaximumLanguageLength } text
            ? text : throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue);

    private static string? Text(JsonNode? value) =>
        value is JsonValue text && text.GetValueKind() == JsonValueKind.String ? text.GetValue<string>() : null;

    #endregion

    #region Actions - Encoding

    public static string SavedTabCloseName(SavedTabClosePolicy policy) =>
        policy == SavedTabClosePolicy.ReturnToSavedUrl ? "returnToSavedURL" : "resumeLastLocation";

    public static JsonObject Rules(AutomaticTranslationRules rules) {
        ArgumentNullException.ThrowIfNull(rules);
        var sources = new JsonObject();
        foreach (var (source, rule) in rules.Sources)
            sources[source] = new JsonObject { [TargetId] = rule.TargetId, [IsEnabled] = rule.IsEnabled };
        return new() { [Sources] = sources };
    }

    #endregion
}
