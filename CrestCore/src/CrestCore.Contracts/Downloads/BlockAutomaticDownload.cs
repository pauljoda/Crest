namespace CrestCore.Contracts;

/// A live automatic download was blocked and waits for the person to retry it.
public sealed record BlockAutomaticDownload(Guid DownloadId) : DownloadIntent;
