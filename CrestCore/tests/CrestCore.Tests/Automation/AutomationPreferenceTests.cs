using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Automation preferences are device state: off until the person turns them
/// on, kept beside the session and never synced. Local tools reach only the
/// Spaces the person allowed of their own session, never a private window's
/// or one being deleted, and see a locked Space's name and nothing more.
public sealed partial class BrowserContractsTests {
    private static AutomationPreferences Automation(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<AutomationPreferencesChanged>()).Preferences;

    [Fact]
    public void AutomationStaysOffUntilChosenAndEveryChoiceSurvivesARelaunch() {
        using var directory = new StorageDirectory();
        var tool = new AutomationTool("crest", "/usr/local/bin/crest");
        AutomationPreferences chosen;
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            var space = SpaceId(spaces[0]!);
            Assert.Equal(AutomationPreferences.Off, app.Query(new GetAutomationPreferences()));
            Assert.Equal(new AutomationReachList(null, []), app.Query(new AutomationReach()));

            // An allowed Space is reached only once automation is on.
            app.Send(new AllowAutomationSpace(space, true));
            Assert.Empty(app.Query(new AutomationReach()).Spaces);
            app.Send(new SetAutomation(true));
            var reach = app.Query(new AutomationReach());
            Assert.Equal(workspace, reach.WorkspaceId);
            Assert.Equal([space], reach.Spaces.Select(reached => reached.SpaceId));
            Assert.False(reach.Spaces[0].IsLocked);

            chosen = Automation(app.Send(new ApproveAutomationTool(tool)));
            Assert.Equal(new AutomationPreferences(true, [space], [tool]), chosen);
            // Approving a tool again, or allowing a Space again, changes nothing.
            Assert.Empty(app.Send(new ApproveAutomationTool(tool)).OfType<AutomationPreferencesChanged>());
            Assert.Empty(app.Send(new AllowAutomationSpace(space, true)).OfType<AutomationPreferencesChanged>());
            Assert.IsType<InvalidAutomationTool>(Assert.Throws<Rejected>(() =>
                app.Send(new ApproveAutomationTool(new AutomationTool("crest", "relative/crest")))).Rejection);
            Assert.IsType<InvalidAutomationTool>(Assert.Throws<Rejected>(() =>
                app.Send(new ApproveAutomationTool(new AutomationTool(" ", "/usr/local/bin/crest")))).Rejection);
        }

        {
            var (relaunched, _, _) = DeviceApp(directory);
            using var disposal = relaunched;
            Assert.Equal(chosen, relaunched.Query(new GetAutomationPreferences()));
            // Turning automation off keeps what the person chose for next time.
            var off = Automation(relaunched.Send(new SetAutomation(false)));
            Assert.Equal(chosen with { IsOn = false }, off);
            Assert.Equal(new AutomationReachList(null, []), relaunched.Query(new AutomationReach()));
            Assert.Empty(Automation(relaunched.Send(new ForgetAutomationTool(tool))).Tools);
        }

        var (third, _, _) = DeviceApp(directory);
        using var thirdDisposal = third;
        Assert.Equal(chosen with { IsOn = false, Tools = [] }, third.Query(new GetAutomationPreferences()));
    }

    [Fact]
    public void ToolsNeverReachAPrivateWindowABorrowedWorkspaceOrAnUnknownSpace() {
        using var app = new CrestApp();
        var session = TwoSpaceSession();
        var first = SpaceId(session["spaces"]![0]!);
        var workspace = TestWorkspaces.Open(app, session);
        app.Send(new SetAutomation(true));
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
        var privateSpace = app.Workspace(privateWorkspace).Current.Spaces[0].Id;
        var borrowed = TestWorkspaces.Borrow(app, workspace, session["spaces"]![0]!);
        Assert.NotEqual(workspace, borrowed);

        foreach (var unavailable in new[] { privateSpace, Guid.NewGuid() })
            Assert.Equal(new AutomationSpaceUnavailable(unavailable), Assert.Throws<Rejected>(() =>
                app.Send(new AllowAutomationSpace(unavailable, true))).Rejection);
        // Stopping a Space it never reached is never refused.
        Assert.Empty(app.Send(new AllowAutomationSpace(privateSpace, false)).OfType<AutomationPreferencesChanged>());

        // A Space a borrowed workspace shows is reached only through the
        // person's own session, which owns it.
        app.Send(new AllowAutomationSpace(first, true));
        Assert.Equal(new AutomationReachList(workspace, [new AutomationSpace(first, Name(session, 0), false)]),
            app.Query(new AutomationReach()));
    }

    [Fact]
    public void ToolsSeeALockedSpacesNameUntilItIsUnlocked() {
        using var app = new CrestApp();
        var session = GuardedSession();
        var workspace = TestWorkspaces.Open(app, session);
        var space = Identity(session).Space;
        app.Send(new SetAutomation(true));
        // Allowing a locked Space reads nothing in it.
        app.Send(new AllowAutomationSpace(space, true));
        Assert.True(Assert.Single(app.Query(new AutomationReach()).Spaces).IsLocked);
        Unlock(app.Send, workspace, space);
        Assert.False(Assert.Single(app.Query(new AutomationReach()).Spaces).IsLocked);
    }

    [Fact]
    public void ASpaceBeingDeletedIsNoLongerReachedAndADeletedOneIsForgotten() {
        using var app = new CrestApp();
        var session = TwoSpaceSession();
        var (first, second) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var workspace = TestWorkspaces.Open(app, session);
        app.Send(new SetAutomation(true));
        app.Send(new AllowAutomationSpace(second, true));
        app.Send(new AllowAutomationSpace(first, true));
        // Tools see the Spaces in the session's order, whatever order they were allowed in.
        Assert.Equal([first, second], app.Query(new AutomationReach()).Spaces.Select(space => space.SpaceId));

        var operation = Guid.NewGuid();
        app.Send(new BeginDeletingSpace(workspace, Guid.NewGuid(), second, operation));
        Assert.Equal([first], app.Query(new AutomationReach()).Spaces.Select(space => space.SpaceId));
        Assert.Equal(new AutomationSpaceUnavailable(second), Assert.Throws<Rejected>(() =>
            app.Send(new AllowAutomationSpace(second, true))).Rejection);

        app.Send(new DeleteProfileData(Guid.NewGuid(), ProfileId(session["spaces"]![1]!), Ephemeral: false));
        var finished = app.Send(new FinishDeletingSpace(workspace, Guid.NewGuid(), second, operation));
        Assert.Equal([first], Automation(finished).SpaceIds);
    }

    private static string Name(JsonNode session, int space) =>
        StoredSessionCodec.DecodeSession(session).Spaces[space].Settings.Name;
}
