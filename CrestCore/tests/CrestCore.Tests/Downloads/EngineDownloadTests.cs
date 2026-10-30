using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// An engine's downloads in the core's ledger: each belongs to its page's
/// Space, the core judges its risk before its file has a place, where its file
/// goes and keeping a file the core or the engine warned about are prompts, the
/// person's row actions reach the engine, and a record's name never carries
/// characters that disguise the file.
public sealed partial class BrowserContractsTests {
    private static EngineDownload Transfer(Guid profile, Guid? page, EngineDownloadState state = EngineDownloadState.Preparing,
        long received = 0, long total = 100, EngineDownloadWarning? warning = null, string token = "",
        EngineDownloadInterruption? interruption = null, string? detail = null) =>
        new("7", profile, page, "report.pdf", Path: null, received, total, new DateTimeOffset(2026, 9, 25, 0, 0, 0, TimeSpan.Zero),
            Restored: false, Paused: false, state, warning, interruption, detail, token);

    /// The engine asking where `download`'s file goes, with the platform's
    /// facts about a file named `name` that it declares as `mime`.
    private static EngineDownloadDestinationRequested Destination(Guid prompt, EngineDownload download, string name,
        string? mime = null, bool userInitiated = true) =>
        new(prompt, download, name, ForcesPrompt: false,
            new DownloadRiskFacts(name, name, mime, ExtensionRunsCode: false, MimeTypeRunsCode: false, TypesRelated: null),
            userInitiated, SourceHost: "files.example");

    private static Guid ProfileOf(CrestApp app, Guid workspace, Guid space) =>
        app.Workspace(workspace).Current.Spaces.First(candidate => candidate.Id == space).ProfileId;

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RecoveryCannotBypassWarningsOrSpaceAccess(bool locksSpace) {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var transfer = Transfer(profile, page, EngineDownloadState.Failed,
            warning: locksSpace ? null : EngineDownloadWarning.PolicyBlocked,
            interruption: EngineDownloadInterruption.Network) with { CanResume = true };
        app.Report(engine, new EngineDownloadChanged(transfer));
        var record = app.Drain().OfType<DownloadUpdated>().Last().Download;
        if (locksSpace) {
            app.Send(new SetSpaceAccess(workspace, space, SpaceAccessPolicy.DeviceOwnerAuthentication));
            app.Send(new LockSpace(space));
        } else {
            Assert.False(record.CanResume);
        }
        var commands = binding.Commands.Count;
        app.Send(new ResumeDownload(record.Id));
        Assert.Equal(commands, binding.Commands.Count);
    }

    [Fact]
    public void ADownloadNoSpaceCanHoldIsCancelledOnItsEngine() {
        var (app, engine, binding, _, _, _, _, _) = LivePage();
        using var disposal = app;
        var stranger = Guid.NewGuid();
        app.Report(engine, new EngineDownloadChanged(Transfer(stranger, page: null, EngineDownloadState.Downloading)));
        Assert.Empty(app.Drain());
        Assert.Equal(new CancelEngineDownload(stranger, "7"), binding.Commands[^1]);
    }

    [Fact]
    public void AWarnedDownloadAsksToBeKeptAndThePersonsRowActionsReachTheEngine() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);

        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.AwaitingApproval,
            warning: EngineDownloadWarning.PotentiallyUnwanted, token: "unwanted")));
        var asked = app.Drain();
        var record = asked.OfType<DownloadUpdated>().Last().Download;
        Assert.Equal(DownloadPhase.AwaitingApproval, record.Phase);
        var approval = Assert.IsType<DownloadApprovalAsked>(asked[^1]);
        Assert.Equal((record.Id, "report.pdf", DownloadWarning.PotentiallyUnwanted),
            (approval.DownloadId, approval.Filename, approval.Warning));
        Assert.Contains(new PromptSettled(approval.PromptId), app.Send(new AnswerDownloadApproval(approval.PromptId, Approved: true)));
        Assert.Equal(new ApproveEngineDownload(profile, "7", "unwanted"), binding.Commands[^1]);

        // The person cancels it from its row, then clears it; a late report brings nothing back.
        app.Send(new CancelDownload(record.Id, "Canceled."));
        Assert.Equal(new CancelEngineDownload(profile, "7"), binding.Commands[^1]);
        app.Send(new RemoveDownload(record.Id));
        Assert.Equal(new RemoveEngineDownload(profile, "7"), binding.Commands[^1]);
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Downloading, received: 80)));
        Assert.Empty(app.Drain());
    }

    [Theory]
    [InlineData("installer.dmg", "application/x-apple-diskimage")]
    [InlineData("invoice\u200B.pdf", "application/pdf")]
    public void ADownloadTheCoreJudgesDangerousIsAskedAboutBeforeItsPlaceAndDecliningCancelsIt(string name, string mime) {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var prompt = Guid.NewGuid();
        var expected = DownloadRiskAssessment.Of(new(name, name, mime, ExtensionRunsCode: false, MimeTypeRunsCode: false,
            TypesRelated: null)).Reasons;
        Assert.NotEmpty(expected);

        // An installer, or a file with a disguised name, the site sent on its
        // own asks first, with the core's reasons, its Space and only the host
        // it came from.
        app.Report(engine, Destination(prompt, Transfer(profile, page) with { Filename = name }, name, mime, userInitiated: false));
        var asked = app.Drain();
        var approval = Assert.IsType<DownloadApprovalAsked>(asked[^1]);
        Assert.Equal(expected, approval.Reasons);
        Assert.Equal((space, DownloadFilename.Safe(name), (DownloadWarning?)null, "files.example"),
            (approval.SpaceId, approval.Filename, approval.Warning, approval.SourceHost));
        Assert.DoesNotContain(asked, change => change is DownloadDestinationAsked);
        Assert.Equal(expected, asked.OfType<DownloadUpdated>().Last().Download.Risk!.Reasons);

        // Declining it cancels it on its engine without asking where it goes.
        var declined = app.Send(new AnswerDownloadApproval(approval.PromptId, Approved: false));
        Assert.Equal(new SettleDownloadDestination(prompt, Path: null), binding.Commands[^1]);
        Assert.DoesNotContain(declined, change => change is DownloadDestinationAsked);
        var canceled = declined.OfType<DownloadUpdated>().Last().Download;
        Assert.Equal((DownloadPhase.Canceled, "Canceled before downloading a potentially dangerous file."),
            (canceled.Phase, canceled.Message));
    }

    [Fact]
    public void AKeptDangerousDownloadIsAskedWhereItGoesAndItsEnginesWarningOfTheSameFactIsNotAskedAgain() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var prompt = Guid.NewGuid();
        var installer = Transfer(profile, page) with { Filename = "installer.dmg" };
        app.Report(engine, Destination(prompt, installer, "installer.dmg", userInitiated: false));
        var approval = app.Drain().OfType<DownloadApprovalAsked>().Single();

        // Keeping it asks where it goes, and only then.
        var kept = app.Send(new AnswerDownloadApproval(approval.PromptId, Approved: true));
        Assert.Equal(new DownloadDestinationAsked(prompt, approval.DownloadId, space, "installer.dmg", ForcesPrompt: false), kept[^1]);
        app.Send(new AnswerDownloadDestination(prompt, "/Users/test/Downloads/installer.dmg"));

        // The engine's warning that the file runs code is what the core
        // already asked about, so the core approves it without asking.
        app.Report(engine, new EngineDownloadChanged(installer with {
            State = EngineDownloadState.AwaitingApproval,
            Warning = EngineDownloadWarning.DangerousFile,
            ApprovalToken = "danger:file"
        }));
        Assert.DoesNotContain(app.Drain(), change => change is DownloadApprovalAsked);
        Assert.Equal(new ApproveEngineDownload(profile, "7", "danger:file"), binding.Commands[^1]);

        // A warning of something new asks, beside the core's reasons.
        app.Report(engine, new EngineDownloadChanged(installer with {
            State = EngineDownloadState.AwaitingApproval,
            Warning = EngineDownloadWarning.InsecureConnection,
            ApprovalToken = "insecure"
        }));
        var insecure = app.Drain().OfType<DownloadApprovalAsked>().Single();
        Assert.Equal((DownloadWarning.InsecureConnection, "files.example"),
            (insecure.Warning, insecure.SourceHost));
        Assert.Equal(DownloadRiskReason.ExecutableOrInstaller, Assert.Single(insecure.Reasons));
    }

    [Theory]
    [InlineData(true, true, true)]
    [InlineData(true, false, true)]
    [InlineData(false, true, false)]
    [InlineData(false, false, true)]
    public void TheChoiceToAskBeforeSavingInstallersCoversOnlyOnesThePersonStarted(bool asks, bool userInitiated, bool expected) {
        // Unless the person chose otherwise, a clicked installer is not asked about.
        Assert.False(AppPreferences.Default.AsksBeforeSavingInstallers);
        var (app, engine, _, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var preferences = app.Workspace(workspace).Current.AppPreferences ?? AppPreferences.Default;
        app.Send(new SetAppPreferences(workspace, preferences with { AsksBeforeSavingInstallers = asks }));
        app.Drain();
        var prompt = Guid.NewGuid();

        // A page that saves an installer without a click is asked about
        // whatever the person chose.
        app.Report(engine, Destination(prompt, Transfer(ProfileOf(app, workspace, space), page) with { Filename = "installer.dmg" },
            "installer.dmg", "application/x-apple-diskimage", userInitiated));
        var asked = app.Drain();
        Assert.Equal(expected, asked.Any(change => change is DownloadApprovalAsked));
        Assert.Equal(!expected, asked[^1] is DownloadDestinationAsked);
    }

    [Fact]
    public void APeeksFirstDownloadIsTheLinkThePersonFollowedButOneAfterItShowsADocumentIsNot() {
        var (app, engine, _, page, workspace, window, space, _) = LivePage();
        using var disposal = app;
        var preferences = app.Workspace(workspace).Current.AppPreferences ?? AppPreferences.Default;
        app.Send(new SetAppPreferences(workspace, preferences with { AsksBeforeSavingInstallers = false }));
        var peek = Guid.NewGuid();
        app.Send(new OpenPage(peek, workspace, space, null, window, TransientPresentation.Peek, OpenerPageId: page));
        app.Report(engine, new PageCreated(peek));
        app.Drain();
        var profile = ProfileOf(app, workspace, space);

        // The engine lost the click's gesture, but the Peek has shown nothing
        // but the link the person followed, so only where it goes is asked.
        app.Report(engine, Destination(Guid.NewGuid(), Transfer(profile, peek) with { Filename = "installer.dmg" }, "installer.dmg",
            "application/x-apple-diskimage", userInitiated: false));
        Assert.IsType<DownloadDestinationAsked>(app.Drain()[^1]);

        // Once it shows a document, that document's own download without a
        // gesture is asked about.
        app.Report(engine, new NavigationCommitted(peek, "https://files.example/", SameDocument: false));
        app.Drain();
        app.Report(engine, Destination(Guid.NewGuid(), Transfer(profile, peek) with { DownloadId = "8", Filename = "installer.dmg" },
            "installer.dmg", "application/x-apple-diskimage", userInitiated: false));
        Assert.IsType<DownloadApprovalAsked>(app.Drain()[^1]);
    }

    [Theory]
    [InlineData("folder/in‮exe.pdf", "inexe.pdf")]
    [InlineData("..\\secret​.txt..", "secret.txt")]
    [InlineData("a:b/c", "c")]
    [InlineData("  ", "download")]
    public void ADownloadsNameKeepsOnlyItsOwnSafeLastComponent(string suggested, string expected) {
        Assert.Equal(expected, DownloadFilename.Safe(suggested));
    }
}
