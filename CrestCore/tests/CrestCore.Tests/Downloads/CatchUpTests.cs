using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A read model that starts after the app hears what it missed: the engines
/// and the shortcuts they offer, the search catalog, every page open now (so a
/// window whose interface loads again shows the pages its engine still holds),
/// every download the core keeps, in its order, then the questions still
/// waiting on the person, each until it settles.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ALateReadModelCatchesUpOnWhatTheDeviceHoldsAndTheQuestionsStillWaiting() {
        var (app, engine, _, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);

        // An engine report asks whether to keep a download it warned about.
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.AwaitingApproval,
            warning: EngineDownloadWarning.DangerousFile, token: "danger:file")));
        var asked = app.Drain();
        var record = asked.OfType<DownloadUpdated>().Last().Download;
        var approval = asked.OfType<DownloadApprovalAsked>().Single();

        var caught = app.Query(new CatchUp()).Changes;
        Assert.Equal(engine.Kind, Assert.Single(Assert.IsType<EnginesChanged>(caught[0]).Roster.Engines).Kind);
        Assert.Contains(Assert.IsType<ShortcutsChanged>(caught[1]).Bindings,
            binding => binding.Command == ShortcutCommand.NewTab && binding.Keys is not null);
        Assert.NotEmpty(Assert.IsType<SearchCatalogChanged>(caught[2]).Providers);
        Assert.Equal(page, Assert.IsType<PageOpened>(caught[3]).Page.Id);
        Assert.Equal(new Change[] { new DownloadUpdated(record, 0), approval }, caught.Skip(4));

        // Once the person answers, the question no longer waits; the download stays.
        app.Send(new AnswerDownloadApproval(approval.PromptId, Approved: false));
        caught = app.Query(new CatchUp()).Changes;
        Assert.DoesNotContain(caught, change => change is DownloadApprovalAsked);
        Assert.Equal(record.Id, Assert.IsType<DownloadUpdated>(Assert.Single(caught.Skip(4))).Download.Id);
    }
}
