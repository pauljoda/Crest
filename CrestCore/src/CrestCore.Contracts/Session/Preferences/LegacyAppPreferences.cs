namespace CrestCore.Contracts;

/// The behavior preferences as an older release's settings stored them, each
/// null when it was never saved. Terms are the stored spellings, which the core
/// reads tolerantly, and `TranslationRules` is the rule set as the settings
/// stored it, a JSON document.
public sealed record LegacyAppPreferences(
    string? StartupBehavior,
    bool? OffersTranslation,
    bool? AutomaticallyTranslates,
    string? TranslationRules,
    bool? ChecksSpelling,
    bool? AutomaticallyEntersPictureInPicture,
    string? SavedTabClosePolicy,
    bool? SavedTabFaviconReturnsToSavedUrl,
    bool? SplitFocusFollowsMouse);
