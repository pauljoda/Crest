namespace CrestCore.Contracts;

/// Records a live download's risk. Any reason makes it wait for approval under
/// its sanitized name.
public sealed record AssessDownloadRisk(Guid DownloadId, DownloadRiskAssessment Assessment) : DownloadIntent;
