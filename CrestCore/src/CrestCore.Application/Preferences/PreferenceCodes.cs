using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the `preferences.*` commands: each preference's name, which
/// is also its stored member, and the command arguments. Values use the stored
/// spellings `StoredSessionCodec` reads.
internal static class PreferenceCodes {
    #region Variables

    public const string Startup = StoredSessionCodec.Key.StartupBehavior;
    public const string OffersTranslation = StoredSessionCodec.Key.OffersTranslation;
    public const string AutomaticallyTranslates = StoredSessionCodec.Key.AutomaticallyTranslates;
    public const string ChecksSpelling = StoredSessionCodec.Key.ChecksSpelling;
    public const string AutomaticallyEntersPictureInPicture = StoredSessionCodec.Key.AutomaticallyEntersPictureInPicture;
    public const string SavedTabClose = StoredSessionCodec.Key.SavedTabClosePolicy;
    public const string SavedTabFaviconReturnsToSavedUrl = StoredSessionCodec.Key.SavedTabFaviconReturnsToSavedUrl;
    public const string SplitFocusFollowsMouse = StoredSessionCodec.Key.SplitFocusFollowsMouse;
    public const string Record = "preferences";
    public const string PreferenceName = "preference";
    public const string PreferenceValue = "value";
    public const string Legacy = "legacy";
    public const string SourceId = "sourceID";
    public const string TargetId = "targetID";
    public const string IsEnabled = "isEnabled";

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

    public static bool? Flag(JsonNode? value) =>
        value is JsonValue flag && flag.GetValueKind() is JsonValueKind.True or JsonValueKind.False ? flag.GetValue<bool>() : null;

    /// A language identifier, which may be empty when nothing was detected.
    public static string Language(JsonNode? value) =>
        Text(value) is { Length: <= AutomaticTranslationRules.MaximumLanguageLength } text
            ? text : throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue);

    private static string? Text(JsonNode? value) =>
        value is JsonValue text && text.GetValueKind() == JsonValueKind.String ? text.GetValue<string>() : null;

    #endregion
}
