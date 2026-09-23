namespace CrestCore.Domain;

/// One behavior preference a settings edit changes. Translation rules are edited
/// per source language rather than replaced whole.
public enum BrowserPreference {
    Startup,
    OffersTranslation,
    AutomaticallyTranslates,
    ChecksSpelling,
    AutomaticallyEntersPictureInPicture,
    SavedTabClose,
    SavedTabFaviconReturnsToSavedUrl,
    SplitFocusFollowsMouse
}
