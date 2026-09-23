namespace CrestCore.Contracts;

/// A live download was canceled.
public sealed record CancelDownload(Guid DownloadId, string Message) : DownloadIntent;
