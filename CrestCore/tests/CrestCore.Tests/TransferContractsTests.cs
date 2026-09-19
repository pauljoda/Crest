using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static Adapter[] TransferAdapters => DeletionAdapters.Select(a => a.Role != "engine" ? a : a with
    { Capabilities = new Dictionary<string, Capability>(a.Capabilities) { ["workspace-transfer"] = new("supported", 1, "test", [], "contract suite") } }).ToArray();
    private static JsonObject TransferTarget(BrowserWorkspace source, BrowserWorkspace destination, WindowId window, TabId tab) => new()
    {
        ["sourceWorkspaceId"] = source.Id.Value.ToString(), ["destinationWorkspaceId"] = destination.Id.Value.ToString(),
        ["spaceId"] = source.Spaces[0].Id.Value.ToString(), ["tabId"] = tab.Value.ToString(), ["windowId"] = window.Value.ToString()
    };
    private static IReadOnlyList<Outgoing> Reassignment(BrowserSessionKernel core, Outgoing effect, bool success = true)
    {
        var body = new JsonObject();
        foreach (var key in new[] { "workspaceId", "spaceId", "tabId", "profileId", "pageId", "generation" })
            body[key] = effect.Payload[key]!.DeepClone();
        return core.Process(Message(success ? "engine.page_reassigned" : "engine.page_reassignment_failed", body,
            "engine", effect.Id, effect.CorrelationId));
    }
    private static (BrowserSessionKernel Core, WindowId SourceWindow, BrowserWorkspace Destination, WindowId DestinationWindow, BrowserTab Tab) TransferKernel()
    {
        var core = new BrowserSessionKernel(TransferAdapters);
        var window = new WindowId(Guid.NewGuid());
        core.Process(Message("core.open_window", new() { ["windowId"] = window.Value.ToString() }));
        var (destination, destinationWindow, _) = CreateWorkspace(core, core.Workspace, "borrowed");
        var page = Open(core, core.Workspace, window);
        AckSurfaces(core, core.Process(Message("engine.page_created", Observation(page), "engine", page.Id, page.CorrelationId)));
        return (core, window, destination, destinationWindow, core.Workspace.Spaces[0].Tabs.Single());
    }
    [Fact]
    public void WorkspaceTransferWaitsForDetachAndRetainsExactNativePageWithoutArchiveOrNavigation()
    {
        var (core, sourceWindow, destination, window, tab) = TransferKernel();
        var page = tab.PageId; var generation = tab.Generation;
        var begin = core.Process(Message("core.transfer_tab", TransferTarget(core.Workspace, destination, window, tab.Id)));
        Assert.Single(core.Workspace.Spaces[0].Tabs); Assert.Empty(destination.Spaces[0].Tabs);
        Assert.DoesNotContain(begin, e => e.Type == "engine.reassign_page");
        var detached = AckSurfaces(core, begin);
        var reassign = detached.Single(e => e.Type == "engine.reassign_page");
        Assert.Empty(destination.Spaces[0].Tabs);
        var committed = Reassignment(core, reassign);
        Assert.Same(tab, destination.Spaces[0].Tabs.Single()); Assert.Empty(core.Workspace.Spaces[0].Tabs);
        Assert.Empty(core.Workspace.Spaces[0].Archive); Assert.Equal(page, tab.PageId); Assert.Equal(generation, tab.Generation);
        Assert.Null(core.Workspace.Window(sourceWindow).Selection(destination.Spaces[0].Id));
        Assert.Equal(tab.Id, destination.Window(window).Selection(destination.Spaces[0].Id));
        Assert.DoesNotContain(committed, e => e.Type is "engine.create_page" or "engine.navigate" or "engine.close_page");
    }
    [Fact]
    public void FailedNativeTransferRestoresSourceAndQueuedWindowCloseDrainsAfterItsOutcome()
    {
        var (core, sourceWindow, destination, window, tab) = TransferKernel();
        var begin = core.Process(Message("core.transfer_tab", TransferTarget(core.Workspace, destination, window, tab.Id)));
        var effect = AckSurfaces(core, begin).Single(e => e.Type == "engine.reassign_page");
        var queued = core.Process(Message("core.close_window", new() { ["windowId"] = window.Value.ToString() }));
        Assert.Empty(queued); Assert.Single(destination.Windows);
        var failed = Reassignment(core, effect, false);
        Assert.Same(tab, core.Workspace.Spaces[0].Tabs.Single()); Assert.Empty(destination.Spaces[0].Tabs);
        Assert.Equal(tab.Id, core.Workspace.Window(sourceWindow).Selection(core.Workspace.Spaces[0].Id));
        Assert.Empty(destination.Windows); Assert.Single(failed, e => e.Type == "engine.release_workspace");
        Assert.Contains(failed, e => e.Payload["code"]?.GetValue<string>() == "native_transfer_failed");
    }
    [Fact]
    public void TransferRejectsPrivateBoundaryAndStaleNativeAcknowledgment()
    {
        var (core, _, destination, window, tab) = TransferKernel();
        var (privateWorkspace, privateWindow, _) = CreateWorkspace(core, core.Workspace, "private");
        var rejected = core.Process(Message("core.transfer_tab", TransferTarget(core.Workspace, privateWorkspace, privateWindow, tab.Id)));
        Assert.Contains(rejected, e => e.Type == "core.operation_failed");
        Assert.Same(tab, core.Workspace.Spaces[0].Tabs.Single()); Assert.Empty(privateWorkspace.Spaces[0].Tabs);
        var begin = core.Process(Message("core.transfer_tab", TransferTarget(core.Workspace, destination, window, tab.Id)));
        var effect = AckSurfaces(core, begin).Single(e => e.Type == "engine.reassign_page");
        var wrong = new JsonObject();
        foreach (var key in new[] { "workspaceId", "spaceId", "tabId", "profileId", "pageId", "generation" }) wrong[key] = effect.Payload[key]!.DeepClone();
        wrong["generation"] = "2";
        Assert.Contains(core.Process(Message("engine.page_reassigned", wrong, "engine", effect.Id, effect.CorrelationId)),
            e => e.Payload["code"]?.GetValue<string>() == "wrong_transfer_page");
        Assert.Empty(destination.Spaces[0].Tabs);
        Reassignment(core, effect); Assert.Same(tab, destination.Spaces[0].Tabs.Single());
        Assert.Empty(Reassignment(core, effect));
    }
}
