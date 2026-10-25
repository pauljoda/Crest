using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The recent tab switcher walks a window's Space from the tab it shows back
/// through the active tabs used most recently, passing over web pages waiting
/// unloaded but not a Start Page, which needs no page. A split is one stop
/// holding all its members, and the first step is the tab the most recent
/// tab's shortcut shows.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void RecentTabsLeadWithTheShownTabThenTheMostRecentlyUsedActiveStops() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));
        foreach (var tab in new[] { f.C1, f.A, f.P2, f.C5 })
            device.ShowPage(window, f.Space, tab, PageSnapshot.Blank with { Url = $"https://recent.example/{tab}" });
        foreach (var tab in new[] { f.A, f.C2, f.N, f.P2, f.C5 }) {
            device.Clock.Now += TimeSpan.FromMinutes(1);
            device.Send(new ShowTab(window, f.Space, tab));
        }

        var order = device.Query(new RecentTabs(window)).Stops;
        Assert.Equal([f.C5, f.P2, f.N, f.A, f.C1], order.Select(stop => stop.TabId));
        Assert.Equal(f.Split, order[3].SplitGroupId);
        Assert.Equal([f.A, f.B], order[3].Members);
        Assert.All(order.Where(stop => stop.SplitGroupId is null), stop => Assert.Equal([stop.TabId], stop.Members));

        device.Clock.Now += TimeSpan.FromMinutes(1);
        device.Send(new ShowMostRecentTab(window));
        Assert.Equal(order[1].TabId, device.Tab(window, f.Space));
        Assert.Equal([f.P2, f.C5, f.N, f.A, f.C1], device.Query(new RecentTabs(window)).Stops.Select(stop => stop.TabId));

        device.Send(new ShowTab(window, f.Space, null));
        Assert.Empty(device.Query(new RecentTabs(window)).Stops);
    }
}
