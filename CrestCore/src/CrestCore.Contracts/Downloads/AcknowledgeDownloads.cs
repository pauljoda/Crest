namespace CrestCore.Contracts;

/// Opening a profile's downloads acknowledges its records without clearing them.
public sealed record AcknowledgeDownloads(Guid ProfileId) : DownloadIntent;
