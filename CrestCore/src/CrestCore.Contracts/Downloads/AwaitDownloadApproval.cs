namespace CrestCore.Contracts;

/// A live download waits for the person's approval.
public sealed record AwaitDownloadApproval(Guid DownloadId) : DownloadIntent;
