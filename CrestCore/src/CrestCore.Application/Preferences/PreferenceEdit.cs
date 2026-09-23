using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// One decoded `preferences.*` command. `preferences.set` carries `preference`
/// and `value`; `preferences.translation_rule` carries `sourceID`, `targetID`
/// and `isEnabled`; `preferences.import` carries `legacy`, the values the native
/// settings stored before the core owned them.
internal sealed record PreferenceEdit(SessionOperation Operation, BrowserPreference? Preference = null,
    JsonNode? Value = null, string? SourceId = null, string? TargetId = null, bool? IsEnabled = null,
    JsonObject? Legacy = null) {
    #region Actions - Decoding

    public static PreferenceEdit Decode(SessionOperation operation, JsonObject? arguments) {
        var args = arguments ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue);
        return operation switch {
            SessionOperation.PreferencesSet => new(operation, PreferenceCodes.Preference(args[PreferenceCodes.PreferenceName]),
                args[PreferenceCodes.PreferenceValue]?.DeepClone()),
            SessionOperation.PreferencesTranslationRule => new(operation,
                SourceId: PreferenceCodes.Language(args[PreferenceCodes.SourceId]),
                TargetId: PreferenceCodes.Language(args[PreferenceCodes.TargetId]),
                IsEnabled: PreferenceCodes.Flag(args[PreferenceCodes.IsEnabled])
                    ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue)),
            SessionOperation.PreferencesImport => new(operation,
                Legacy: args[PreferenceCodes.Legacy] as JsonObject
                    ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue)),
            _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownPreferenceCommand)
        };
    }

    #endregion

    #region Actions - Preferences

    /// The preferences after this edit. An import applies only while the
    /// session has no record, so a later launch never imports over a choice.
    public BrowserPreferences Apply(JsonNode? stored) {
        var current = PreferencesDocument.Read(stored);
        return Operation switch {
            SessionOperation.PreferencesImport => stored is null ? PreferencesDocument.Import(Legacy!) : current,
            SessionOperation.PreferencesTranslationRule => current.WithTranslationRule(SourceId!, TargetId!, IsEnabled!.Value),
            _ => Set(current)
        };
    }

    private BrowserPreferences Set(BrowserPreferences current) => Preference switch {
        BrowserPreference.Startup => current with {
            Startup = PreferenceCodes.StartupValue(Value) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue)
        },
        BrowserPreference.SavedTabClose => current with {
            SavedTabClose = PreferenceCodes.SavedTabCloseValue(Value)
                ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue)
        },
        { } flag => current.With(flag,
            PreferenceCodes.Flag(Value) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue)),
        null => throw new BrowserRuleException(BrowserRuleCodes.UnknownPreference)
    };

    #endregion
}
