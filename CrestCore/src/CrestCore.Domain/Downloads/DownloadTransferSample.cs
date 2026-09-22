namespace CrestCore.Domain;

/// One published transfer reading: row telemetry and a progress in [0, 1].
public sealed record DownloadTransferSample(DownloadTelemetry Telemetry, double Progress);
