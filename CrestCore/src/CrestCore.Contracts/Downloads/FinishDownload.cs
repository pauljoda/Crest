namespace CrestCore.Contracts;

/// A live download finished with the bytes actually written, when known.
public sealed record FinishDownload(Guid DownloadId, long? FinalByteCount) : DownloadIntent;
