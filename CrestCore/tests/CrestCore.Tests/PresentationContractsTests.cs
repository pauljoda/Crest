using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static JsonObject SurfaceAck(Outgoing effect) => new()
    { ["windowId"] = effect.Payload["windowId"]!.DeepClone(), ["leaseId"] = effect.Payload["leaseId"]!.DeepClone() };

    [Fact]
    public void StartPageDraftIsReusedLocallyAndConvertedInPlace()
    {
        var (core, window, space) = Kernel();
        var request = new JsonObject { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString() };
        var created = core.Process(Message("core.new_tab", request));
        var draft = Assert.Single(core.Workspace.Space(space).Tabs);
        Assert.Equal(TabKind.StartPage, draft.Kind); Assert.Null(draft.PageId);
        Assert.DoesNotContain(created, e => e.Recipient == "engine");
        core.Process(Message("core.new_tab", request));
        Assert.Same(draft, Assert.Single(core.Workspace.Space(space).Tabs));
        var otherWindow = new WindowId(Guid.NewGuid()); core.Workspace.AddWindow(otherWindow);
        core.Process(Message("core.new_tab", new() { ["windowId"] = otherWindow.Value.ToString(), ["spaceId"] = space.Value.ToString() }));
        Assert.Equal(draft.Id, core.Workspace.Window(window).Selection(space));
        Assert.NotEqual(draft.Id, core.Workspace.Window(otherWindow).Selection(space));
        var navigate = core.Process(Message("core.navigate_input", new()
        { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString(), ["input"] = "example.org" }));
        var effect = navigate.Single(e => e.Type == "engine.create_page");
        Assert.Equal(draft.Id.Value.ToString(), effect.Payload["tabId"]!.GetValue<string>());
        Assert.Equal(TabKind.Web, draft.Kind);
        Assert.Equal(2, core.Workspace.Space(space).Tabs.Count);
    }

    [Fact]
    public void NativeFeatureAndWebTabKeepDistinctPanesInTheSameSplit()
    {
        var (core, window, space) = Kernel(); var web = Open(core, window, space);
        core.Process(Message("engine.page_created", Observation(web), "engine", web.Id, web.CorrelationId));
        var webTab = Assert.Single(core.Workspace.Space(space).Tabs);
        core.Process(Message("core.open_settings", new()
        { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString(), ["disposition"] = "foreground" }));
        var native = core.Workspace.Space(space).Tabs.Single(t => t.Kind == TabKind.Settings);
        var join = Selection(window, space, native.Id); join["targetTabId"] = webTab.Id.Value.ToString();
        var split = core.Process(Message("core.join_split", join));
        var presentation = split.Single(e => e.Type == "platform.assign_surface");
        Assert.Single(presentation.Payload["pages"]!.AsArray());
        var panes = presentation.Payload["panes"]!.AsArray();
        Assert.Equal(new[] { webTab.Id.Value.ToString(), native.Id.Value.ToString() }, panes.Select(p => p!["tabId"]!.GetValue<string>()));
        Assert.Equal("settings", panes[1]!["kind"]!.GetValue<string>()); Assert.Null(panes[1]!["pageId"]);
        Assert.DoesNotContain(split, e => e.Type == "engine.create_page");
    }

    [Fact]
    public void NativePageTransfersOnlyAfterItsOldSurfaceHasDetached()
    {
        var (core, source, space) = Kernel(); var create = Open(core, source, space);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = core.Workspace.Space(space).Tabs.Single(); var destination = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(destination);
        var select = Message("core.select_tab", Selection(destination, space, tab.Id));
        var detaching = core.Process(select).Single();
        Assert.Equal(source.Value.ToString(), detaching.Payload["windowId"]!.GetValue<string>());
        Assert.Null(detaching.Payload["pageId"]);
        Assert.Equal(tab.Id, core.Workspace.Window(source).Selection(space));
        Assert.Null(core.Workspace.Window(destination).Selection(space));
        var completed = core.Process(Message("platform.surface_attached", SurfaceAck(detaching), "platform", detaching.Id, detaching.CorrelationId));
        Assert.Null(core.Workspace.Window(source).Selection(space));
        Assert.Equal(tab.Id, core.Workspace.Window(destination).Selection(space));
        Assert.Contains(completed, e => e.Type == "platform.assign_surface" && e.Payload["pageId"]?.GetValue<string>() == tab.PageId!.Value.Value.ToString());
        Assert.DoesNotContain(completed, e => e.Type == "core.operation_completed" && e.CorrelationId == select.CorrelationId);
        var attaching = completed.Single(e => e.Type == "platform.assign_surface" && e.Payload["windowId"]!.GetValue<string>() == destination.Value.ToString());
        var attached = core.Process(Message("platform.surface_attached", SurfaceAck(attaching), "platform", attaching.Id, attaching.CorrelationId));
        Assert.Contains(attached, e => e.Type == "core.operation_completed" && e.CorrelationId == select.CorrelationId);
        Assert.DoesNotContain(completed, e => e.Type == "engine.create_page");
    }

    [Fact]
    public void SplitPresentationMaterializesAllMembersAndRollsBackTheWholeGroupAfterFailedAttachment()
    {
        var (core, source, space) = Kernel();
        var first = Open(core, source, space);
        core.Process(Message("engine.page_created", Observation(first), "engine", first.Id, first.CorrelationId));
        var firstTab = core.Workspace.Space(space).Tabs.Single();
        var second = Open(core, source, space);
        core.Process(Message("engine.page_created", Observation(second), "engine", second.Id, second.CorrelationId));
        var secondTab = core.Workspace.Space(space).Tabs.Single(t => t.Id != firstTab.Id);
        var join = Selection(source, space, secondTab.Id); join["targetTabId"] = firstTab.Id.Value.ToString();
        var joined = core.Process(Message("core.join_split", join));
        Assert.Equal(2, joined.Single(e => e.Type == "platform.assign_surface").Payload["pages"]!.AsArray().Count);
        Assert.Equal(source, core.Workspace.PresentingWindow(space, firstTab.Id)!.Id);
        var destination = new WindowId(Guid.NewGuid()); core.Workspace.AddWindow(destination);
        var select = Message("core.select_tab", Selection(destination, space, firstTab.Id));
        var detach = core.Process(select).Single();
        var transferring = core.Process(Message("platform.surface_attached", SurfaceAck(detach), "platform", detach.Id, detach.CorrelationId));
        var attach = transferring.Single(e => e.Type == "platform.assign_surface" && e.Payload["windowId"]!.GetValue<string>() == destination.Value.ToString());
        Assert.Equal(2, attach.Payload["pages"]!.AsArray().Count);
        Assert.Equal(destination, core.Workspace.PresentingWindow(space, secondTab.Id)!.Id);
        var failed = core.Process(Message("platform.failed", SurfaceAck(attach), "platform", attach.Id, attach.CorrelationId));
        Assert.Equal(secondTab.Id, core.Workspace.Window(source).Selection(space));
        Assert.Null(core.Workspace.Window(destination).Selection(space));
        Assert.Equal(source, core.Workspace.PresentingWindow(space, firstTab.Id)!.Id);
        Assert.Contains(failed, e => e.Type == "core.operation_failed" && e.CorrelationId == select.CorrelationId);
        Assert.Empty(core.Process(Message("platform.surface_attached", SurfaceAck(attach), "platform", attach.Id, attach.CorrelationId)));
        Assert.Equal(0, core.PendingEffectCount);
    }

    [Fact]
    public void RestoredSplitHasOneWindowOwnerAndCreatesEveryDormantMember()
    {
        var (original, source, space) = Kernel(); Open(original, source, space); Open(original, source, space);
        var members = original.Workspace.Space(space).Tabs;
        original.Workspace.Space(space).JoinSplit(members[1].Id, members[0].Id, null, new SystemIdSource(), DateTimeOffset.UtcNow);
        var document = new LegacySessionDocument(); var state = document.Write(original.Workspace.Capture());
        var core = new BrowserKernel(Adapters, initialState: state);
        var restored = core.Process(Message("core.open_window", new() { ["windowId"] = source.Value.ToString() }));
        Assert.Equal(2, restored.Count(e => e.Type == "engine.create_page"));
        Assert.Equal(2, core.Workspace.PresentedTabs(source).Count);
        var creations = restored.Where(e => e.Type == "engine.create_page").ToArray();
        foreach (var creation in creations)
            core.Process(Message("engine.page_created", Observation(creation), "engine", creation.Id, creation.CorrelationId));
        Assert.All(core.Workspace.PresentedTabs(source), t => Assert.Equal(TabPhase.Ready, t.Phase));
    }

    [Fact]
    public void SupersededTransferCannotStealASelectionAfterALateDetach()
    {
        var (core, source, space) = Kernel(); var create = Open(core, source, space);
        var tab = core.Workspace.Space(space).Tabs.Single(); var destination = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(destination);
        var detaching = core.Process(Message("core.select_tab", Selection(destination, space, tab.Id))).Single();
        // A late creation must not replace the outstanding detach lease.
        var created = core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        Assert.DoesNotContain(created, e => e.Type == "platform.assign_surface");
        var canceled = core.Process(Message("core.select_tab", Selection(destination, space)));
        Assert.Contains(canceled, e => e.Payload["code"]?.GetValue<string>() == "canceled");
        Assert.Empty(core.Process(Message("platform.surface_attached", SurfaceAck(detaching), "platform", detaching.Id, detaching.CorrelationId)));
        Assert.Equal(tab.Id, core.Workspace.Window(source).Selection(space));
        Assert.Null(core.Workspace.Window(destination).Selection(space));
        Assert.Equal(0, core.PendingEffectCount);
    }

    [Fact]
    public void ClosingSavedPageRetainsItsDescriptorAndFencesTheNextNativeGeneration()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = core.Workspace.Space(space).Tabs.Single(); var oldPage = tab.PageId;
        core.Workspace.PlaceTab(space, tab.Id, TabPlacement.Saved, null);
        var close = core.Process(Message("core.close_tab", Selection(window, space, tab.Id))).Single(e => e.Type == "engine.close_page");
        core.Process(Message("engine.page_closed", Observation(close), "engine", close.Id, close.CorrelationId));
        Assert.Single(core.Workspace.Space(space).Tabs); Assert.Empty(core.Workspace.Space(space).Archive);
        Assert.Equal(TabPhase.Dormant, tab.Phase); Assert.Null(tab.PageId); Assert.Null(core.Workspace.Window(window).Selection(space));
        var recreated = core.Process(Message("core.select_tab", Selection(window, space, tab.Id))).Single(e => e.Type == "engine.create_page");
        Assert.NotEqual(oldPage, tab.PageId); Assert.Equal("2", recreated.Payload["generation"]!.GetValue<string>());
        Assert.Contains(core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId)), e => e.Type == "core.operation_failed");
    }

    [Fact]
    public void RestoringAnArchivedPagePreservesIdentityAndHistoryCoalescesFragments()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = core.Workspace.Space(space).Tabs.Single();
        tab.Observe("https://example.com/article#first", "First", false, false, false, null); core.Workspace.Visit(space, tab.Id);
        tab.Observe("https://example.com/article#second", "Second", false, false, false, null); core.Workspace.Visit(space, tab.Id);
        var visit = Assert.Single(core.Workspace.Space(space).History);
        Assert.Equal(2, visit.VisitCount); Assert.Equal("https://example.com/article", visit.Url);
        core.Workspace.RenameTab(space, tab.Id, "Reading"); core.Workspace.Close(space, tab.Id);
        var restored = core.Process(Message("core.restore_tab", Selection(window, space, tab.Id)));
        Assert.Empty(core.Workspace.Space(space).Archive);
        Assert.Equal("Reading", core.Workspace.Space(space).Tab(tab.Id).DisplayTitle);
        Assert.Contains(restored, e => e.Type == "engine.create_page");
    }
}
