namespace CrestCore.Domain;

/// The filename a download is saved under and every reason it looks dangerous,
/// in a stable order. No reasons means the file is ordinary.
public sealed record DownloadRiskAssessment(string SanitizedFilename, IReadOnlyList<DownloadRiskReason> Reasons);
