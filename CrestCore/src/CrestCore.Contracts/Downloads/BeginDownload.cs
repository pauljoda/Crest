namespace CrestCore.Contracts;

/// Records a new download as preparing, ahead of every existing record. The
/// caller supplies the identity and creation time so a retried call is
/// deterministic. A download an engine restored from an earlier run starts
/// acknowledged.
public sealed record BeginDownload(Guid DownloadId, Guid ProfileId, string Filename, DateTimeOffset CreatedAt,
    bool IsAcknowledged) : DownloadIntent;
