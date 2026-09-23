namespace CrestCore.Domain;

/// The app-wide behavior preferences of one installation: what a window opens
/// with, page translation, spelling, automatic Picture in Picture, what closing
/// a saved tab does and whether Split View focus follows the pointer. They are
/// device-local and never become sync records. Appearance preferences are not
/// part of this state.
public sealed record BrowserPreferences(StartupBehavior Startup, bool OffersTranslation, bool AutomaticallyTranslates,
    AutomaticTranslationRules TranslationRules, bool ChecksSpelling, bool AutomaticallyEntersPictureInPicture,
    SavedTabClosePolicy SavedTabClose, bool SavedTabFaviconReturnsToSavedUrl, bool SplitFocusFollowsMouse) {
    #region Variables

    /// The documented defaults for a person who never chose.
    public static BrowserPreferences Default { get; } = new(LaunchPolicy.DefaultStartup, OffersTranslation: true,
        AutomaticallyTranslates: false, AutomaticTranslationRules.Empty, ChecksSpelling: false,
        AutomaticallyEntersPictureInPicture: true, SavedTabClosePolicy.ResumeLastLocation,
        SavedTabFaviconReturnsToSavedUrl: false, SplitFocusFollowsMouse: false);

    #endregion

    #region Mutators

    /// Records the new choice for one flag preference.
    public BrowserPreferences With(BrowserPreference preference, bool value) => preference switch {
        BrowserPreference.OffersTranslation => this with { OffersTranslation = value },
        BrowserPreference.AutomaticallyTranslates => this with { AutomaticallyTranslates = value },
        BrowserPreference.ChecksSpelling => this with { ChecksSpelling = value },
        BrowserPreference.AutomaticallyEntersPictureInPicture => this with { AutomaticallyEntersPictureInPicture = value },
        BrowserPreference.SavedTabFaviconReturnsToSavedUrl => this with { SavedTabFaviconReturnsToSavedUrl = value },
        BrowserPreference.SplitFocusFollowsMouse => this with { SplitFocusFollowsMouse = value },
        _ => throw new BrowserRuleException(BrowserRuleCodes.InvalidPreferenceValue)
    };

    /// Records a source language's translation choice through the rule set's
    /// alias rules.
    public BrowserPreferences WithTranslationRule(string source, string target, bool isEnabled) =>
        this with { TranslationRules = TranslationRules.Set(source, target, isEnabled) };

    #endregion
}
