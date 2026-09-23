using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Reads and writes the session's `appPreferences` record. It sits beside the
/// Spaces in the session checkpoint, so it persists with them, and it is never
/// projected into sync records. Fields this build does not know are kept.
internal static class PreferencesDocument {
    #region Variables

    public const string Field = "appPreferences";

    #endregion

    #region Actions - Persistence

    /// Missing or unreadable fields read as their defaults.
    public static BrowserPreferences Read(JsonNode? stored) {
        var defaults = BrowserPreferences.Default;
        return new(PreferenceCodes.StartupValue(stored?[PreferenceCodes.Startup]) ?? defaults.Startup,
            PreferenceCodes.Flag(stored?[PreferenceCodes.OffersTranslation]) ?? defaults.OffersTranslation,
            PreferenceCodes.Flag(stored?[PreferenceCodes.AutomaticallyTranslates]) ?? defaults.AutomaticallyTranslates,
            PreferenceCodes.Rules(stored?[PreferenceCodes.TranslationRules]),
            PreferenceCodes.Flag(stored?[PreferenceCodes.ChecksSpelling]) ?? defaults.ChecksSpelling,
            PreferenceCodes.Flag(stored?[PreferenceCodes.AutomaticallyEntersPictureInPicture])
                ?? defaults.AutomaticallyEntersPictureInPicture,
            PreferenceCodes.SavedTabCloseValue(stored?[PreferenceCodes.SavedTabClose]) ?? defaults.SavedTabClose,
            PreferenceCodes.Flag(stored?[PreferenceCodes.SavedTabFaviconReturnsToSavedUrl])
                ?? defaults.SavedTabFaviconReturnsToSavedUrl,
            PreferenceCodes.Flag(stored?[PreferenceCodes.SplitFocusFollowsMouse]) ?? defaults.SplitFocusFollowsMouse);
    }

    public static JsonObject Write(JsonNode? stored, BrowserPreferences preferences) {
        ArgumentNullException.ThrowIfNull(preferences);
        var value = stored is JsonObject original ? original.DeepClone().AsObject() : new JsonObject();
        value[PreferenceCodes.Startup] = LaunchCodes.Startup(preferences.Startup);
        value[PreferenceCodes.OffersTranslation] = preferences.OffersTranslation;
        value[PreferenceCodes.AutomaticallyTranslates] = preferences.AutomaticallyTranslates;
        value[PreferenceCodes.TranslationRules] = PreferenceCodes.Rules(preferences.TranslationRules);
        value[PreferenceCodes.ChecksSpelling] = preferences.ChecksSpelling;
        value[PreferenceCodes.AutomaticallyEntersPictureInPicture] = preferences.AutomaticallyEntersPictureInPicture;
        value[PreferenceCodes.SavedTabClose] = PreferenceCodes.SavedTabCloseName(preferences.SavedTabClose);
        value[PreferenceCodes.SavedTabFaviconReturnsToSavedUrl] = preferences.SavedTabFaviconReturnsToSavedUrl;
        value[PreferenceCodes.SplitFocusFollowsMouse] = preferences.SplitFocusFollowsMouse;
        return value;
    }

    #endregion

    #region Actions - Migration

    /// The values the native settings stored before the core owned them, each
    /// under its preference name and null when never saved. Translation rules
    /// arrive as the raw JSON text the native setting stored. A value this build
    /// cannot read keeps its default rather than failing the whole import.
    public static BrowserPreferences Import(JsonObject legacy) {
        ArgumentNullException.ThrowIfNull(legacy);
        var stored = legacy.DeepClone().AsObject();
        stored[PreferenceCodes.TranslationRules] = RawRules(legacy[PreferenceCodes.TranslationRules]);
        return Read(stored);
    }

    private static JsonNode? RawRules(JsonNode? value) {
        if (value is not JsonValue text || text.GetValueKind() != JsonValueKind.String) return null;
        try {
            return JsonNode.Parse(text.GetValue<string>(), documentOptions: new() { MaxDepth = 8 });
        } catch (JsonException) {
            return null;
        }
    }

    #endregion
}
