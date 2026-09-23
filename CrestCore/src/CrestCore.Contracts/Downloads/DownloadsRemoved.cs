namespace CrestCore.Contracts;

/// Download records that were cleared, expired or removed with their profile.
public sealed record DownloadsRemoved(IReadOnlyList<Guid> DownloadIds) : Change;
