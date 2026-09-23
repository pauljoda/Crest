namespace CrestCore.Contracts;

/// Transfer telemetry, progress or a final byte count is negative or not a number.
public sealed record InvalidDownloadProgress() : Rejection;
