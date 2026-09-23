namespace CrestCore.Contracts;

/// Why a download looks dangerous and whether, given how it started, the
/// person must confirm it before it continues.
public sealed record DownloadRisk(DownloadRiskFacts Facts, bool IsUserInitiated) : Query<DownloadRiskVerdict>;
