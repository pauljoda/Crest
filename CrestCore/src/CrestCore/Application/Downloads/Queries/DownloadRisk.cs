using CrestCore.Application;

namespace CrestCore.Contracts;

/// Why a download looks dangerous and whether, given how it started and the
/// app's choice to ask before saving apps and installers, the person must
/// confirm it before it continues.
public sealed record DownloadRisk(DownloadRiskFacts Facts, bool IsUserInitiated) : Query<DownloadRiskVerdict> {
    #region Actions - Answering

    /// The engines' downloads ask the ledger the same question.
    internal override DownloadRiskVerdict Answer(CrestApp app) =>
        app.Downloads.Answer(this, (app.Device.PersistentPreferences() ?? AppPreferences.Default).AsksBeforeSavingInstallers);

    #endregion
}
