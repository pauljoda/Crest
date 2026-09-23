namespace CrestCore.Contracts;

/// Deleting a profile's data removes every record it owns, live or not. The
/// caller cancels the matching transfers.
public sealed record RemoveProfileDownloads(Guid ProfileId) : DownloadIntent;
