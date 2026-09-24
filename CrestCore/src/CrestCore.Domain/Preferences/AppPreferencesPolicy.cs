using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The app-wide behavior preferences a person who never chose starts with, and
/// how each settings edit changes them.
public static class AppPreferencesPolicy {
    #region Variables

    /// The documented defaults for a person who never chose.
    public static AppPreferences Default { get; } = new(LaunchPolicy.DefaultStartup, OffersTranslation: true,
        AutomaticallyTranslates: false, AutomaticTranslationRules.Empty.Sources, ChecksSpelling: false,
        AutomaticallyEntersPictureInPicture: true, SavedTabClosePolicy.ResumeLastLocation,
        SavedTabFaviconReturnsToSavedUrl: false, SplitFocusFollowsMouse: false);

    #endregion

    #region Actions - Preferences

    /// Records the new choice for one flag preference.
    public static AppPreferences With(this AppPreferences preferences, BrowserPreference preference, bool value) => preference switch {
        BrowserPreference.OffersTranslation => preferences with { OffersTranslation = value },
        BrowserPreference.AutomaticallyTranslates => preferences with { AutomaticallyTranslates = value },
        BrowserPreference.ChecksSpelling => preferences with { ChecksSpelling = value },
        BrowserPreference.AutomaticallyEntersPictureInPicture => preferences with { AutomaticallyEntersPictureInPicture = value },
        BrowserPreference.SavedTabFaviconReturnsToSavedUrl => preferences with { SavedTabFaviconReturnsToSavedUrl = value },
        BrowserPreference.SplitFocusFollowsMouse => preferences with { SplitFocusFollowsMouse = value },
        _ => throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue)
    };

    /// Records a source language's translation choice through the rule set's
    /// alias rules.
    public static AppPreferences WithTranslationRule(this AppPreferences preferences, string source, string target, bool isEnabled) =>
        preferences with {
            TranslationRules = AutomaticTranslationRules.Restore(preferences.TranslationRules).Set(source, target, isEnabled).Sources
        };

    #endregion
}
