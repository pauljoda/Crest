using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static Adapter[] WorkspaceAdapters => AuthenticationAdapters.Select(a => a.Role != "engine" ? a : a with
    { Capabilities = new Dictionary<string, Capability>(a.Capabilities) { ["workspace-profiles"] = new("supported", 1, "test", [], "contract suite") } }).ToArray();
    private static (BrowserWorkspace Workspace, WindowId Window, IReadOnlyList<Outgoing> Output) CreateWorkspace(
        BrowserSessionKernel core, BrowserWorkspace source, string mode)
    {
        var window = new WindowId(Guid.NewGuid());
        var output = core.Process(Message("core.create_workspace", new()
        {
            ["windowId"] = window.Value.ToString(), ["sourceWorkspaceId"] = source.Id.Value.ToString(),
            ["spaceId"] = source.Spaces[0].Id.Value.ToString(), ["mode"] = mode
        }));
        return (core.Workspaces.Single(w => w.Windows.Any(n => n.Id == window)), window, output);
    }
    private static Outgoing Open(BrowserSessionKernel core, BrowserWorkspace workspace, WindowId window) =>
        core.Process(Message("core.open_tab", new() { ["windowId"] = window.Value.ToString(),
            ["workspaceId"] = workspace.Id.Value.ToString(), ["spaceId"] = workspace.Spaces[0].Id.Value.ToString(),
            ["url"] = "https://example.com", ["disposition"] = "foreground" })).Single(e => e.Type == "engine.create_page");
    private static void Release(BrowserSessionKernel core, Outgoing effect) => core.Process(Message("engine.workspace_released",
        new() { ["workspaceId"] = effect.Payload["workspaceId"]!.DeepClone() }, "engine", effect.Id, effect.CorrelationId));

    [Fact]
    public void BorrowedWorkspaceSharesOnlyProfilePolicyAndKeepsItsRecordsOutOfDurableStorage()
    {
        var storage = Adapter("services") with { Capabilities = new Dictionary<string, Capability>
            { ["session-storage"] = new("supported", 1, "test", [], "contract suite") } };
        var core = new BrowserSessionKernel([.. WorkspaceAdapters, storage], persistSession: true);
        var rootWindow = new WindowId(Guid.NewGuid());
        var initial = core.Process(Message("core.open_window", new() { ["windowId"] = rootWindow.Value.ToString() }));
        var save = initial.Single(e => e.Type == "services.save_session");
        core.Process(Message("services.session_saved", new() { ["revision"] = save.Payload["revision"]!.DeepClone() }, "services", save.Id, save.CorrelationId));
        var root = core.Workspace;
        var (temporary, window, creation) = CreateWorkspace(core, root, "borrowed");
        Assert.NotEqual(root.Id, temporary.Id); Assert.Empty(temporary.Spaces[0].Tabs);
        Assert.Equal(root.Spaces[0].Id, temporary.Spaces[0].Id);
        Assert.Equal(root.Spaces[0].ProfileId, temporary.Spaces[0].ProfileId);
        Assert.DoesNotContain(creation, e => e.Recipient == "services");
        var page = Open(core, temporary, window);
        var ready = core.Process(Message("engine.page_created", Observation(page), "engine", page.Id, page.CorrelationId));
        Assert.Empty(root.Spaces[0].Tabs); Assert.Single(temporary.Spaces[0].Tabs);
        Assert.DoesNotContain(ready, e => e.Recipient == "services");
        var rename = core.Process(Message("core.rename_space", new() { ["workspaceId"] = temporary.Id.Value.ToString(),
            ["spaceId"] = temporary.Spaces[0].Id.Value.ToString(), ["name"] = "Shared policy" }));
        Assert.Equal("Shared policy", root.Spaces[0].Name); Assert.Equal(root.Spaces[0].Name, temporary.Spaces[0].Name);
        var saved = rename.Single(e => e.Type == "services.save_session").Payload["state"]!.ToJsonString();
        Assert.DoesNotContain(temporary.Spaces[0].Tabs[0].Id.Value.ToString().ToUpperInvariant(), saved);
        Assert.Single(temporary.Spaces[0].Tabs);
    }
    [Fact]
    public void PrivateProfileIsDistinctAndLastWindowDisposalWaitsForCreationWithoutNavigating()
    {
        var core = new BrowserSessionKernel(WorkspaceAdapters);
        var (workspace, window, _) = CreateWorkspace(core, core.Workspace, "private");
        Assert.NotEqual(core.Workspace.Spaces[0].ProfileId, workspace.Spaces[0].ProfileId);
        Assert.Equal("duckDuckGo", workspace.Spaces[0].Search.SelectedId);
        Assert.Equal(CurrentTabCleanup.Never, workspace.Spaces[0].Retention.CurrentTabs);
        var page = Open(core, workspace, window);
        Assert.Equal("private", page.Payload["profileMode"]!.GetValue<string>());
        var closing = core.Process(Message("core.close_window", new() { ["windowId"] = window.Value.ToString() }));
        Assert.DoesNotContain(closing, e => e.Type == "engine.release_workspace");
        var finished = core.Process(Message("engine.page_created", Observation(page), "engine", page.Id, page.CorrelationId));
        Assert.DoesNotContain(finished, e => e.Type == "engine.navigate");
        var release = finished.Single(e => e.Type == "engine.release_workspace");
        Assert.Single(release.Payload["releaseProfiles"]!.AsArray());
        Assert.Equal(1, core.PendingEffectCount);
        Release(core, release);
        Assert.Equal(0, core.PendingEffectCount); Assert.Single(core.Workspaces);
    }
    [Fact]
    public void ProfileOwnerOutlivesBorrowerAndPrivateDisposalReleasesBorrowersFirst()
    {
        var core = new BrowserSessionKernel(WorkspaceAdapters);
        var (owner, window, _) = CreateWorkspace(core, core.Workspace, "private");
        var (borrower, _, _) = CreateWorkspace(core, owner, "borrowed");
        var closing = AckSurfaces(core, core.Process(Message("core.close_window", new() { ["windowId"] = window.Value.ToString() })));
        var first = Assert.Single(closing, e => e.Type == "engine.release_workspace");
        Assert.Equal(borrower.Id.Value.ToString(), first.Payload["workspaceId"]!.GetValue<string>());
        Assert.Empty(first.Payload["releaseProfiles"]!.AsArray());
        var secondOutput = core.Process(Message("engine.workspace_released", new() { ["workspaceId"] = borrower.Id.Value.ToString() },
            "engine", first.Id, first.CorrelationId));
        var second = Assert.Single(secondOutput, e => e.Type == "engine.release_workspace");
        Assert.Equal(owner.Id.Value.ToString(), second.Payload["workspaceId"]!.GetValue<string>());
        Release(core, second); Assert.Equal(0, core.PendingEffectCount); Assert.Single(core.Workspaces);
    }
    [Fact]
    public void WorkspaceAndNativePageRoutingCannotCrossRecordOwnership()
    {
        var core = new BrowserSessionKernel(WorkspaceAdapters);
        var (first, firstWindow, _) = CreateWorkspace(core, core.Workspace, "private");
        var (second, secondWindow, _) = CreateWorkspace(core, core.Workspace, "private");
        var page = Open(core, first, firstWindow);
        var forged = Observation(page); forged["workspaceId"] = second.Id.Value.ToString();
        Assert.Contains(core.Process(Message("engine.page_created", forged, "engine", page.Id, page.CorrelationId)),
            e => e.Payload["code"]?.GetValue<string>() == "wrong_workspace");
        Assert.Equal(TabPhase.Creating, first.Spaces[0].Tabs[0].Phase);
        var wrong = new JsonObject { ["windowId"] = secondWindow.Value.ToString(), ["workspaceId"] = first.Id.Value.ToString(),
            ["spaceId"] = first.Spaces[0].Id.Value.ToString() };
        Assert.Contains(core.Process(Message("core.new_tab", wrong)), e => e.Payload["code"]?.GetValue<string>() == "wrong_workspace");
        Assert.Empty(second.Spaces[0].Tabs);
    }
    [Fact]
    public void BorrowedAuthenticationUsesCanonicalPolicyAndCannotImportSourceTabs()
    {
        var core = new BrowserSessionKernel(WorkspaceAdapters);
        var rootWindow = new WindowId(Guid.NewGuid()); core.Process(Message("core.open_window", new() { ["windowId"] = rootWindow.Value.ToString() }));
        var root = core.Workspace; var (borrowed, window, _) = CreateWorkspace(core, root, "borrowed");
        var foreignPolicy = core.Process(Message("core.rename_space", new() { ["workspaceId"] = borrowed.Id.Value.ToString(),
            ["spaceId"] = root.Spaces[1].Id.Value.ToString(), ["name"] = "Wrong profile" }));
        Assert.Contains(foreignPolicy, e => e.Payload["code"]?.GetValue<string>() == "wrong_profile");
        Assert.Equal("Work", root.Spaces[1].Name);
        var target = new JsonObject { ["windowId"] = window.Value.ToString(), ["spaceId"] = borrowed.Spaces[0].Id.Value.ToString(), ["requiresAuthentication"] = true };
        core.Process(Message("core.set_space_access", target));
        Assert.True(root.Spaces[0].IsLocked); Assert.True(borrowed.Spaces[0].IsLocked);
        target.Remove("requiresAuthentication");
        var request = core.Process(Message("core.unlock_space", target)).Single(e => e.Type == "platform.authenticate_space");
        var forged = AuthenticationReply(request); forged["profileId"] = Guid.NewGuid().ToString();
        core.Process(Message("platform.authentication_completed", forged, "platform", request.Id, request.CorrelationId));
        Assert.True(borrowed.Spaces[0].IsLocked);
        core.Process(Message("platform.authentication_completed", AuthenticationReply(request), "platform", request.Id, request.CorrelationId));
        Assert.False(root.Spaces[0].IsLocked); Assert.False(borrowed.Spaces[0].IsLocked); Assert.Empty(borrowed.Spaces[0].Tabs);
    }
    [Fact]
    public void AdditionalPrivateSpacesKeepPrivateDefaultsAndNeverPersist()
    {
        var core = new BrowserSessionKernel(DeletionAdapters);
        var (workspace, _, _) = CreateWorkspace(core, core.Workspace, "private");
        var output = core.Process(Message("core.create_space", new()
            { ["workspaceId"] = workspace.Id.Value.ToString(), ["name"] = "Private research" }));
        var created = workspace.Spaces[1];
        Assert.NotEqual(workspace.Spaces[0].ProfileId, created.ProfileId);
        Assert.Equal("duckDuckGo", created.Search.SelectedId);
        Assert.False(created.Search.SuggestionsEnabled);
        Assert.Equal(CurrentTabCleanup.Never, created.Retention.CurrentTabs);
        Assert.DoesNotContain(output, e => e.Recipient == "services");
    }
    [Fact]
    public void LateNativeAdoptionCannotEscapeAClosedTemporaryWorkspace()
    {
        var core = new BrowserSessionKernel(WorkspaceAdapters);
        var (workspace, window, _) = CreateWorkspace(core, core.Workspace, "borrowed");
        var page = Open(core, workspace, window);
        core.Process(Message("engine.page_created", Observation(page), "engine", page.Id, page.CorrelationId));
        var closing = core.Process(Message("core.close_window", new() { ["windowId"] = window.Value.ToString() }));
        var release = closing.Single(e => e.Type == "engine.release_workspace");
        Release(core, release);
        var token = Guid.NewGuid().ToString();
        var rejected = core.Process(Message("engine.adoption_requested", new()
        {
            ["adoptionId"] = token, ["profileId"] = workspace.Spaces[0].ProfileId.Value.ToString(),
            ["sourcePageId"] = page.Payload["pageId"]!.DeepClone(), ["windowId"] = window.Value.ToString(),
            ["url"] = "about:blank", ["foreground"] = true
        }, "engine"));
        Assert.Equal(token, rejected.Single(e => e.Type == "engine.reject_adoption").Payload["adoptionId"]!.GetValue<string>());
        Assert.Empty(core.Workspace.Spaces[0].Tabs);
    }

}
