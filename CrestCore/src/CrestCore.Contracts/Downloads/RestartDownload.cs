namespace CrestCore.Contracts;

/// Retrying a blocked automatic download starts the same record again from
/// nothing and counts as news for the downloads badge.
public sealed record RestartDownload(Guid DownloadId) : DownloadIntent;
