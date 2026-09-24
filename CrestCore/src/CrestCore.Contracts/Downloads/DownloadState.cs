namespace CrestCore.Contracts;

/// One download record owned by a browsing profile. `Message` explains a
/// canceled or failed record and is null in every other phase.
public sealed record DownloadState(Guid Id, Guid ProfileId, DateTimeOffset CreatedAt, string Filename, string? Destination,
    double Progress, DownloadTelemetry Telemetry, DownloadPhase Phase, string? Message, DownloadRiskAssessment? Risk,
    bool IsAcknowledged);
