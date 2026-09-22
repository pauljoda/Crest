using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class DownloadPolicyTests {
    private static DownloadRiskAssessment Assess(string filename, string? mime, bool extensionRunsCode = false,
        bool mimeRunsCode = false, bool? related = null, string? sanitized = null) =>
        DownloadRiskPolicy.Assess(new(filename, sanitized ?? filename, mime, extensionRunsCode, mimeRunsCode, related));

    [Fact]
    public void OrdinaryDocumentsCarryNoRisk() {
        var assessment = Assess("report.pdf", "application/pdf", related: true);
        Assert.Empty(assessment.Reasons);
        Assert.False(DownloadRiskPolicy.RequiresConfirmation(assessment, isUserInitiated: false));
    }

    [Theory]
    [InlineData("update.pkg")]
    [InlineData("tool.command")]
    [InlineData("setup.EXE")]
    [InlineData("profile.mobileconfig")]
    [InlineData("script.PS1")]
    public void InstallerAndScriptExtensionsAreExecutableEvenWithoutPlatformTypes(string filename) {
        var assessment = Assess(filename, "application/octet-stream");
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], assessment.Reasons);
        Assert.True(DownloadRiskPolicy.RequiresConfirmation(assessment, isUserInitiated: false));
    }

    [Fact]
    public void PlatformTypeFactsAndDangerousMimeTypesAlsoMarkExecutables() {
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], Assess("tool.py", "text/plain", extensionRunsCode: true).Reasons);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], Assess("blob", "APPLICATION/X-MSDOWNLOAD").Reasons);
        Assert.Empty(Assess("archive.", null).Reasons);
    }

    [Fact]
    public void UserInitiatedInstallersRelyOnThePlatformProtection() {
        var assessment = Assess("Crest.dmg", "application/x-apple-diskimage", true, true, true);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], assessment.Reasons);
        Assert.False(DownloadRiskPolicy.RequiresConfirmation(assessment, isUserInitiated: true));
        Assert.True(DownloadRiskPolicy.RequiresConfirmation(assessment, isUserInitiated: false));
    }

    [Theory]
    [InlineData("photo.jpg\u202Egpj.command")]
    [InlineData("invoice\u200B.pdf")]
    [InlineData("\uFEFFnotes.txt")]
    [InlineData("list\u2067.txt")]
    public void DirectionChangingOrInvisibleCharactersAreDeceptiveWhateverTheActivation(string filename) {
        var assessment = Assess(filename, "application/octet-stream", sanitized: "renamed.txt");
        Assert.Contains(DownloadRiskReason.DeceptiveFilename, assessment.Reasons);
        Assert.Equal("renamed.txt", assessment.SanitizedFilename);
        Assert.True(DownloadRiskPolicy.RequiresConfirmation(assessment, isUserInitiated: true));
    }

    [Fact]
    public void ADangerousTypeThatDisagreesWithItsFilenameIsAMismatch() {
        var mismatch = Assess("holiday.jpg", "application/x-mach-binary", mimeRunsCode: true, related: false);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller, DownloadRiskReason.DangerousTypeMismatch], mismatch.Reasons);
        Assert.True(DownloadRiskPolicy.RequiresConfirmation(mismatch, isUserInitiated: true));
        Assert.DoesNotContain(DownloadRiskReason.DangerousTypeMismatch,
            Assess("holiday.jpg", "application/x-mach-binary", mimeRunsCode: true, related: null).Reasons);
        Assert.Empty(Assess("holiday.jpg", "image/png", related: false).Reasons);
    }

    [Fact]
    public void UserInitiatedDownloadsAndApprovedRetriesBypassSavedDenials() {
        Assert.Equal(AutomaticDownloadAction.Allow,
            AutomaticDownloadPolicy.Decide(true, false, SitePermissionDecision.DenyPersistently, true).Action);
        var retry = AutomaticDownloadPolicy.Decide(false, true, SitePermissionDecision.DenyPersistently, true);
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, true), retry);
    }

    [Theory]
    [InlineData(SitePermissionDecision.GrantForSession, AutomaticDownloadAction.Allow)]
    [InlineData(SitePermissionDecision.GrantPersistently, AutomaticDownloadAction.Allow)]
    [InlineData(SitePermissionDecision.DenyForSession, AutomaticDownloadAction.Deny)]
    [InlineData(SitePermissionDecision.DenyPersistently, AutomaticDownloadAction.Deny)]
    public void SavedDecisionsAnswerAutomaticDownloadsWithoutThrottling(SitePermissionDecision decision,
        AutomaticDownloadAction expected) {
        var verdict = AutomaticDownloadPolicy.Decide(false, false, decision, true);
        Assert.Equal(expected, verdict.Action);
        Assert.Equal(new AutomaticDownloadVerdict(expected, false),
            AutomaticDownloadPolicy.Decide(false, false, decision, false));
    }

    [Fact]
    public void TheFirstAutomaticDownloadIsAllowedAndAUserActionResetsTheAllowance() {
        var first = AutomaticDownloadPolicy.Decide(false, false, SitePermissionDecision.Ask, false);
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, true), first);
        var second = AutomaticDownloadPolicy.Decide(false, false, SitePermissionDecision.Ask, first.HasAllowedAutomaticDownload);
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.RequestPermission, true), second);
        var gesture = AutomaticDownloadPolicy.Decide(true, false, SitePermissionDecision.Ask, second.HasAllowedAutomaticDownload);
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, false), gesture);
        Assert.Equal(AutomaticDownloadAction.Allow,
            AutomaticDownloadPolicy.Decide(false, false, SitePermissionDecision.Ask, gesture.HasAllowedAutomaticDownload).Action);
    }

    [Fact]
    public void EstimatorKeepsBytesMonotonicAndSmoothsRateAndEstimate() {
        var estimator = default(DownloadTransferEstimator);
        (estimator, _) = estimator.Sample(0, 10_000, 0, false, 0);
        (estimator, var first) = estimator.Sample(1_000, 10_000, 0.1, false, 1);
        (estimator, var noisy) = estimator.Sample(3_000, 10_000, 0.3, false, 2);
        (_, var regressed) = estimator.Sample(2_500, 10_000, 0.25, false, 3);

        Assert.Equal(1_000, first.Telemetry.BytesPerSecond!.Value, 3);
        Assert.Equal(9, first.Telemetry.EstimatedTimeRemaining!.Value, 3);
        Assert.Equal(1_250, noisy.Telemetry.BytesPerSecond!.Value, 3);
        Assert.Equal(5.6, noisy.Telemetry.EstimatedTimeRemaining!.Value, 3);
        Assert.Equal(3_000, regressed.Telemetry.BytesReceived);
        Assert.Equal(0.3, regressed.Progress, 3);
    }

    [Fact]
    public void EstimatorWaitsForAUsefulIntervalAndPausingClearsTheRate() {
        var estimator = default(DownloadTransferEstimator);
        (estimator, _) = estimator.Sample(0, 1_000, 0, false, 0);
        (estimator, var early) = estimator.Sample(100, 1_000, 0.1, false, 0.1);
        Assert.Null(early.Telemetry.BytesPerSecond);
        (estimator, var paused) = estimator.Sample(200, 1_000, 0.2, true, 1);
        Assert.True(paused.Telemetry.IsPaused);
        Assert.Null(paused.Telemetry.BytesPerSecond);
        Assert.Null(paused.Telemetry.EstimatedTimeRemaining);
        (_, var resumed) = estimator.Sample(400, 1_000, 0.4, false, 2);
        Assert.Equal(200, resumed.Telemetry.BytesPerSecond!.Value, 3);
    }

    [Fact]
    public void ADisprovedTotalIsDiscardedAndUselessEstimatesAreHidden() {
        var estimator = default(DownloadTransferEstimator);
        (estimator, _) = estimator.Sample(0, 100, 0, false, 0);
        (estimator, var disproved) = estimator.Sample(500, 100, 0.5, false, 1);
        Assert.Null(disproved.Telemetry.TotalBytes);
        Assert.Null(disproved.Telemetry.EstimatedTimeRemaining);
        Assert.Equal(0.5, disproved.Progress);
        (_, var later) = estimator.Sample(600, 10_000, 0.06, false, 2);
        Assert.Null(later.Telemetry.TotalBytes);

        var slow = default(DownloadTransferEstimator);
        (slow, _) = slow.Sample(0, long.MaxValue / 2, 0, false, 0);
        (_, var glacial) = slow.Sample(1, long.MaxValue / 2, 0, false, 1);
        Assert.Null(glacial.Telemetry.EstimatedTimeRemaining);
        Assert.Throws<BrowserRuleException>(() => slow.Sample(1, 1, 0, false, double.NaN));
    }
}
