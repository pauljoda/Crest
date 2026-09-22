namespace CrestCore.Domain;

/// One download record owned by a browsing profile. `CreatedAt` and every time
/// compared with it are seconds in one caller-chosen epoch. `Message` explains a
/// canceled or failed record and is null in every other state.
public sealed record DownloadItem(Guid Id, Guid Profile, double CreatedAt, string Filename, string? Destination,
    double Progress, DownloadTelemetry Telemetry, DownloadItemState State, string? Message,
    DownloadRiskAssessment? Risk, bool IsAcknowledged) {
    #region Variables

    /// A live transfer still owned by an engine or a pending prompt.
    public bool IsActive => State is DownloadItemState.Preparing or DownloadItemState.AwaitingApproval
        or DownloadItemState.Downloading;

    #endregion
}
