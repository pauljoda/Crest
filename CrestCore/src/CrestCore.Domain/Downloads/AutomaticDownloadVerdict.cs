namespace CrestCore.Domain;

/// The action for one download and the throttle state its page and origin
/// carry into the next automatic download.
public readonly record struct AutomaticDownloadVerdict(AutomaticDownloadAction Action, bool HasAllowedAutomaticDownload);
