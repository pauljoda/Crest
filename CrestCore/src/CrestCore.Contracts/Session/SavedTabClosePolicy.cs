namespace CrestCore.Contracts;

/// <summary>Where a pinned or saved tab opens after it is closed: the page it last
/// showed, or its saved URL.</summary>
public enum SavedTabClosePolicy { ResumeLastLocation, ReturnToSavedUrl }
