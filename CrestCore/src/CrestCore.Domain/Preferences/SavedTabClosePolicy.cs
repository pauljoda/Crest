namespace CrestCore.Domain;

/// Where a pinned or saved tab opens after it is closed: the page it last
/// showed, or its saved URL.
public enum SavedTabClosePolicy { ResumeLastLocation, ReturnToSavedUrl }
