namespace CrestCore.Contracts;

/// Names the file a live download writes. The record's filename follows the
/// destination's.
public sealed record SetDownloadDestination(Guid DownloadId, string Destination, string Filename) : DownloadIntent;
