namespace CrestCore.Contracts;

/// One transfer reading for a live download. Progress never moves backwards.
public sealed record RecordDownloadTransfer(Guid DownloadId, DownloadTelemetry Telemetry, double Progress)
    : DownloadIntent;
