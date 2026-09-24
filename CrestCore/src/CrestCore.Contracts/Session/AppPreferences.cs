namespace CrestCore.Contracts;

/// <summary>
/// The app-wide behavior preferences of one installation: what a window opens with,
/// page translation and its per-language rules, spelling, automatic Picture in
/// Picture, what closing a saved tab does and whether Split View focus follows the
/// pointer. Translation rules are in ordinal order of their source language. They
/// stay on this device and never become sync records.
/// </summary>
public sealed record AppPreferences(StartupBehavior Startup, bool OffersTranslation, bool AutomaticallyTranslates,
    IReadOnlyList<TranslationRule> TranslationRules, bool ChecksSpelling, bool AutomaticallyEntersPictureInPicture,
    SavedTabClosePolicy SavedTabClose, bool SavedTabFaviconReturnsToSavedUrl, bool SplitFocusFollowsMouse) {
    #region Actions - Equality

    public bool Equals(AppPreferences? other) => other is not null
        && Startup == other.Startup
        && OffersTranslation == other.OffersTranslation
        && AutomaticallyTranslates == other.AutomaticallyTranslates
        && TranslationRules.SequenceEqual(other.TranslationRules)
        && ChecksSpelling == other.ChecksSpelling
        && AutomaticallyEntersPictureInPicture == other.AutomaticallyEntersPictureInPicture
        && SavedTabClose == other.SavedTabClose
        && SavedTabFaviconReturnsToSavedUrl == other.SavedTabFaviconReturnsToSavedUrl
        && SplitFocusFollowsMouse == other.SplitFocusFollowsMouse;

    public override int GetHashCode() => HashCode.Combine(Startup, OffersTranslation, AutomaticallyTranslates,
        TranslationRules.Count, ChecksSpelling, AutomaticallyEntersPictureInPicture, SavedTabClose,
        HashCode.Combine(SavedTabFaviconReturnsToSavedUrl, SplitFocusFollowsMouse));

    #endregion
}
