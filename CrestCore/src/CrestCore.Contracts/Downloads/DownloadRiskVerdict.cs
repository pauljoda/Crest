namespace CrestCore.Contracts;

/// A download's risk assessment and whether the person must confirm it.
public sealed record DownloadRiskVerdict(DownloadRiskAssessment Assessment, bool RequiresConfirmation);
