namespace CrestCore.Contracts;

/// One published transfer reading: the estimator state to send with the next
/// sample, the row telemetry and a progress in [0, 1].
public sealed record DownloadProgressReading(DownloadTransferEstimator Estimator, DownloadTelemetry Telemetry, double Progress);
