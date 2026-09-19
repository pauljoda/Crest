using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static Adapter[] ResidencyAdapters => Adapters.Select(a => a.Role != "engine" ? a : a with
    { Capabilities = new Dictionary<string, Capability>(a.Capabilities)
        { ["page-residency"] = new("supported", 1, "test", [], "residency contract") } }).ToArray();
    private static JsonObject Pressure(string level = "critical", string platform = "desktop") => new()
    { ["level"] = level, ["platform"] = platform };
    private static (BrowserKernel Core, WindowId Window, BrowserSpace Space, BrowserTab Tab, Outgoing Create) InactivePage()
    {
        var core = new BrowserKernel(ResidencyAdapters); var window = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(window); var space = core.Workspace.Spaces[0];
        var create = Open(core, window, space.Id);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = Assert.Single(space.Tabs);
        core.Process(Message("core.select_tab", Selection(window, space.Id)));
        return (core, window, space, tab, create);
    }
    [Fact]
    public void MemoryPressureProtectsSelectionsAndKeepLoadedPagesAcrossWindows()
    {
        var (core, window, space, tab, _) = InactivePage();
        tab.SetResidency(true);
        Assert.Empty(core.Process(Message("platform.memory_pressure", Pressure(), "platform")));
        tab.SetResidency(false);
        var secondWindow = new WindowId(Guid.NewGuid()); core.Workspace.AddWindow(secondWindow);
        core.Workspace.Select(secondWindow, space.Id, tab.Id);
        Assert.Empty(core.Process(Message("platform.memory_pressure", Pressure(), "platform")));
        core.Workspace.Select(secondWindow, space.Id, null);
        Assert.Empty(core.Process(Message("platform.memory_pressure", Pressure(platform: "mobile", level: "warning"), "platform")));
        var unloaded = core.Process(Message("platform.memory_pressure", Pressure(platform: "mobile"), "platform"));
        Assert.Single(unloaded, o => o.Type == "engine.unload_page");
        Assert.Equal(TabPhase.Unloading, tab.Phase); Assert.Single(space.Tabs); Assert.Empty(space.Archive);
    }
    [Fact]
    public void SelectingDuringUnloadWaitsAndRestoresWithANewPageGeneration()
    {
        var (core, window, space, tab, _) = InactivePage();
        var effect = core.Process(Message("core.release_inactive_pages", Pressure())).Single(o => o.Type == "engine.unload_page");
        var originalPage = tab.PageId;
        var selected = core.Process(Message("core.select_tab", Selection(window, space.Id, tab.Id)));
        Assert.DoesNotContain(selected, o => o.Type == "engine.create_page");
        Assert.All(selected.Where(o => o.Type == "platform.assign_surface"), o => Assert.Empty(o.Payload["pages"]!.AsArray()));
        var forged = core.Process(Message("engine.page_unloaded", Observation(effect), "engine", Guid.NewGuid(), effect.CorrelationId));
        Assert.Contains(forged, o => o.Type == "core.operation_failed"); Assert.Equal(TabPhase.Unloading, tab.Phase);
        var output = core.Process(Message("engine.page_unloaded", Observation(effect), "engine", effect.Id, effect.CorrelationId));
        var create = Assert.Single(output, o => o.Type == "engine.create_page");
        Assert.NotEqual(originalPage, tab.PageId); Assert.Equal(2UL, tab.Generation);
        Assert.Single(space.Tabs); Assert.Empty(space.Archive);
        var completion = Observation(create); completion["generation"] = "2"; completion["restored"] = true;
        var restored = core.Process(Message("engine.page_created", completion, "engine", create.Id, create.CorrelationId));
        Assert.DoesNotContain(restored, o => o.Type == "engine.navigate"); Assert.Equal(TabPhase.Ready, tab.Phase);
        var stale = core.Process(Message("engine.page_unloaded", Observation(effect), "engine", effect.Id, effect.CorrelationId));
        Assert.Contains(stale, o => o.Type == "core.operation_failed"); Assert.Equal(TabPhase.Ready, tab.Phase);
    }
    [Fact]
    public void CanceledUnloadPreservesTheNativePageAndDefersConflictingClosure()
    {
        var (core, window, space, tab, _) = InactivePage(); var originalPage = tab.PageId;
        var effect = core.Process(Message("core.release_inactive_pages", Pressure())).Single(o => o.Type == "engine.unload_page");
        var close = core.Process(Message("core.close_tab", Selection(window, space.Id, tab.Id)));
        Assert.Contains(close, o => o.Payload["code"]?.GetValue<string>() == "page_unloading");
        Assert.DoesNotContain(close, o => o.Type == "engine.close_page");
        core.Process(Message("core.select_tab", Selection(window, space.Id, tab.Id)));
        var canceled = core.Process(Message("engine.unload_canceled", Observation(effect), "engine", effect.Id, effect.CorrelationId));
        Assert.Equal(originalPage, tab.PageId); Assert.Equal(TabPhase.Ready, tab.Phase);
        Assert.Contains(canceled, o => o.Type == "platform.assign_surface" && o.Payload["pages"]!.AsArray().Count == 1);
        Assert.Empty(space.Archive);
    }
    [Fact]
    public void ShutdownDrainsUnloadWithoutRecreatingASelectedPage()
    {
        var (core, window, space, tab, _) = InactivePage();
        var effect = core.Process(Message("core.release_inactive_pages", Pressure())).Single(o => o.Type == "engine.unload_page");
        core.Process(Message("core.select_tab", Selection(window, space.Id, tab.Id)));
        core.BeginShutdown(); Assert.True(core.PendingEffectCount > 0);
        var output = core.Process(Message("engine.page_unloaded", Observation(effect), "engine", effect.Id, effect.CorrelationId));
        Assert.DoesNotContain(output, o => o.Type == "engine.create_page");
        Assert.Equal(TabPhase.Dormant, tab.Phase); Assert.Null(tab.PageId);
        Assert.Equal(tab.Id, core.Workspace.Window(window).Selection(space.Id)); Assert.Empty(space.Archive);
    }
}
