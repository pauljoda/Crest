using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private sealed class TestClock : IClock { public DateTimeOffset Now { get; set; } = new(2026, 9, 19, 12, 0, 0, TimeSpan.Zero); }
    [Fact]
    public void MaintenanceWaitsForNativeCloseAndPreservesCanceledAndSelectedTabs()
    {
        var clock = new TestClock(); var core = new BrowserKernel(Adapters, clock: clock); var window = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(window); var space = core.Workspace.Spaces[0];
        var first = Open(core, window, space.Id);
        core.Process(Message("engine.page_created", Observation(first), "engine", first.Id, first.CorrelationId));
        var oldTab = Assert.Single(space.Tabs);
        clock.Now += TimeSpan.FromDays(2);
        var second = Open(core, window, space.Id);
        core.Process(Message("engine.page_created", Observation(second), "engine", second.Id, second.CorrelationId));
        var selected = core.Workspace.Window(window).Selection(space.Id);
        var close = core.Process(Message("core.maintain_session", new())).Single(e => e.Type == "engine.close_page");
        Assert.Equal(oldTab.Id.Value.ToString(), close.Payload["tabId"]!.GetValue<string>()); Assert.Empty(space.Archive);
        Assert.Empty(core.Process(Message("core.maintain_session", new())));
        core.Process(Message("engine.close_canceled", Observation(close), "engine", close.Id, close.CorrelationId));
        Assert.Equal(2, space.Tabs.Count); Assert.Empty(space.Archive);
        clock.Now += TimeSpan.FromDays(2);
        var retry = core.Process(Message("core.maintain_session", new())).Single(e => e.Type == "engine.close_page");
        core.Process(Message("engine.page_closed", Observation(retry), "engine", retry.Id, retry.CorrelationId));
        Assert.Equal(selected, Assert.Single(space.Tabs).Id);
        Assert.Equal("autoCleanup", Assert.Single(space.Archive).Reason);
    }
    [Fact]
    public void MaintenanceProtectsRememberedSplitsAndRepairsUnclaimedWindowSelectionsAfterClosure()
    {
        var fixture = SavedSession(); var clock = new TestClock();
        var tabs = fixture.Document["session"]!["spaces"]![0]!["tabs"]!.AsArray();
        var companion = (JsonObject)tabs[0]!.DeepClone(); var companionId = Guid.NewGuid();
        companion["id"] = SwiftId(companionId); tabs.Insert(1, companion);
        var core = new BrowserKernel(Adapters, clock: clock, initialState: fixture.Document);
        var space = core.Workspace.Space(fixture.Space);
        core.Process(Message("core.maintain_session", new()));
        Assert.Contains(space.Tabs, t => t.Id == fixture.Tab); // Its owning scene has not connected yet.
        Assert.Contains(space.Tabs, t => t.Id.Value == companionId);
        core.Workspace.Close(space.Id, fixture.Tab, delete: true);
        var restored = core.Workspace.AddWindow(fixture.Window);
        Assert.Null(restored.Selection(space.Id));
        Assert.DoesNotContain(core.Workspace.Capture().Windows, w => w.Selections.Values.Contains(fixture.Tab));
    }
    [Fact]
    public void RetentionUsesLastVisitAndArchiveDatesAndPreservesFuturePreferences()
    {
        var fixture = SavedSession(); var document = new LegacySessionDocument(fixture.Document);
        var workspace = BrowserWorkspace.Restore(document.Read(new SystemIdSource()), new SystemIdSource(), new SystemClock());
        var space = workspace.Spaces[0];
        space.SetRetention(new(CurrentTabCleanup.Never, DataRetention.OneWeek, DataRetention.OneDay, DataRetention.ThirtyDays));
        Assert.True(space.PruneStoredRecords(new DateTimeOffset(2026, 9, 19, 12, 0, 0, TimeSpan.Zero)));
        Assert.Empty(space.History); Assert.Empty(space.Archive);
        var saved = document.Write(workspace.Capture());
        Assert.True(saved["session"]!["spaces"]![0]!["browsingPreferences"]!["futureFlag"]!.GetValue<bool>());
        var restored = new LegacySessionDocument(saved).Read(new SystemIdSource());
        Assert.Equal(space.Retention, restored.Spaces[0].Retention);
    }
}
