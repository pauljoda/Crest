using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The app-wide behavior preferences a person who never chose starts with, and
/// how a translation rule edit changes them.
public static class AppPreferencesPolicy {
    #region Variables

    /// The documented defaults for a person who never chose.
    public static AppPreferences Default { get; } = new(LaunchPolicy.DefaultStartup, OffersTranslation: true,
        AutomaticallyTranslates: false, AutomaticTranslationRules.Empty.Sources, ChecksSpelling: false,
        AutomaticallyEntersPictureInPicture: true, SavedTabClosePolicy.ResumeLastLocation,
        SavedTabFaviconReturnsToSavedUrl: false, SplitFocusFollowsMouse: false);

    #endregion

    #region Actions - Preferences

    /// Records a source language's translation choice through the rule set's
    /// alias rules.
    public static AppPreferences WithTranslationRule(this AppPreferences preferences, string source, string target, bool isEnabled) =>
        preferences with {
            TranslationRules = AutomaticTranslationRules.Restore(preferences.TranslationRules).Set(source, target, isEnabled).Sources
        };

    #endregion
}
