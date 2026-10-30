using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class DownloadPolicyTests {
    private static DownloadRiskAssessment Assess(string filename, string? mime, bool extensionRunsCode = false,
        bool mimeRunsCode = false, bool? related = null, string? sanitized = null) =>
        DownloadRiskAssessment.Of(new(filename, sanitized ?? filename, mime, extensionRunsCode, mimeRunsCode, related));

    [Theory]
    [InlineData("update.pkg")]
    [InlineData("tool.command")]
    [InlineData("setup.EXE")]
    [InlineData("profile.mobileconfig")]
    [InlineData("script.PS1")]
    public void InstallerAndScriptExtensionsAreExecutableEvenWithoutPlatformTypes(string filename) {
        var assessment = Assess(filename, "application/octet-stream");
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], assessment.Reasons);
        Assert.True(assessment.RequiresConfirmation(isUserInitiated: false, asksBeforeSavingInstallers: false));
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
        Assert.True(assessment.RequiresConfirmation(isUserInitiated: true, asksBeforeSavingInstallers: false));
    }

    [Fact]
    public void ADangerousTypeThatDisagreesWithItsFilenameIsAMismatch() {
        var mismatch = Assess("holiday.jpg", "application/x-mach-binary", mimeRunsCode: true, related: false);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller, DownloadRiskReason.DangerousTypeMismatch], mismatch.Reasons);
        Assert.True(mismatch.RequiresConfirmation(isUserInitiated: true, asksBeforeSavingInstallers: false));
        Assert.DoesNotContain(DownloadRiskReason.DangerousTypeMismatch,
            Assess("holiday.jpg", "application/x-mach-binary", mimeRunsCode: true, related: null).Reasons);
        Assert.Empty(Assess("holiday.jpg", "image/png", related: false).Reasons);
    }

    [Theory]
    [InlineData("application/octet-stream")]
    [InlineData("BINARY/OCTET-STREAM")]
    [InlineData("application/force-download")]
    public void AGenericDeclaredTypeIsNoMismatchSoAClickedInstallerIsNotAsked(string mime) {
        var assessment = Assess("Rectangle.dmg", mime, extensionRunsCode: true, related: false);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], assessment.Reasons);
        Assert.False(assessment.RequiresConfirmation(isUserInitiated: true, asksBeforeSavingInstallers: false));
        Assert.True(assessment.RequiresConfirmation(isUserInitiated: false, asksBeforeSavingInstallers: false));
    }

    [Theory]
    [InlineData("grantForSession", "allow")]
    [InlineData("grantPersistently", "allow")]
    [InlineData("denyForSession", "deny")]
    [InlineData("denyPersistently", "deny")]
    public void SavedDecisionsAnswerAutomaticDownloadsWithoutThrottling(string name, string expected) {
        var decision = SitePermissionDecision.Named(name)!;
        var verdict = new AutomaticDownloadCheck(false, false, decision, true).Verdict;
        Assert.Equal(expected, verdict.Action.Name);
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Named(expected)!, false),
            new AutomaticDownloadCheck(false, false, decision, false).Verdict);
    }

    [Fact]
    public void TheFirstAutomaticDownloadIsAllowedAndAUserActionResetsTheAllowance() {
        var first = new AutomaticDownloadCheck(false, false, SitePermissionDecision.Ask, false).Verdict;
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, true), first);
        var second = new AutomaticDownloadCheck(false, false, SitePermissionDecision.Ask, first.HasAllowedAutomaticDownload).Verdict;
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.RequestPermission, true), second);
        var gesture = new AutomaticDownloadCheck(true, false, SitePermissionDecision.Ask, second.HasAllowedAutomaticDownload).Verdict;
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, false), gesture);
        Assert.Equal(AutomaticDownloadAction.Allow,
            new AutomaticDownloadCheck(false, false, SitePermissionDecision.Ask, gesture.HasAllowedAutomaticDownload).Verdict.Action);
    }

}
