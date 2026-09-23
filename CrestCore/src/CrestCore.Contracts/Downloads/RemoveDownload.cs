namespace CrestCore.Contracts;

/// Clears one record. Files already written stay on disk; the caller refuses to
/// clear a record whose transfer it still owns.
public sealed record RemoveDownload(Guid DownloadId) : DownloadIntent;
