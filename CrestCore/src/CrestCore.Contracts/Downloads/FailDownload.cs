namespace CrestCore.Contracts;

/// A live or blocked download failed. A blocked automatic download fails when its
/// retry can no longer be replayed.
public sealed record FailDownload(Guid DownloadId, string Message) : DownloadIntent;
