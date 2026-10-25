using CrestCore.Application;

namespace CrestCore.Contracts;

/// The active tabs of the Space a window shows as the recent tab switcher walks
/// them: most recently used first, starting with the one it shows. A tab is
/// active unless its web page waits unloaded: a Start Page or native view needs
/// no page, and a web page is active while a page holds it. A split the sidebar
/// shows as one row is one stop, where its most recently used active member
/// falls, and showing it shows that member. Empty when the window shows no tab.
public sealed record RecentTabs(Guid WindowId) : Query<RecentTabOrder> {
    #region Actions - Answering

    /// The window's shown tab, then the rest of its Space's active tabs, from
    /// the most recently used, each split folded into its first stop.
    internal override RecentTabOrder Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var session = app.Device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        Guid? shown;
        lock (app.Device.Gate) {
            spaceId = window.ShownSpaceId;
            shown = window.Tab(spaceId);
        }
        if (Device.Available(session, spaceId) is not { } space || shown is not { } tabId) return new([]);
        var splits = space.Sidebar.Lists.SelectMany(list => list.Rows).Where(row => row.Kind.GroupsTabs)
            .SelectMany(row => row.Members.Select(member => (Member: member, Row: row)))
            .ToDictionary(pair => pair.Member, pair => pair.Row);
        var walked = space.Tabs
            .Where(tab => tab.Id != tabId
                && (!tab.Surface.ShowsPage || app.Pages.Showing(window.WorkspaceId, WindowId, tab.Id) is not null))
            .OrderByDescending(tab => tab.LastActivatedAt).Select(tab => tab.Id).Prepend(tabId);
        var folded = new HashSet<Guid>();
        var stops = new List<RecentTabStop>();
        foreach (var id in walked) {
            if (!splits.TryGetValue(id, out var split)) {
                stops.Add(new(id, null, [id]));
            } else if (folded.Add(split.Id)) {
                stops.Add(new(id, split.Id, split.Members));
            }
        }
        return new(stops);
    }

    #endregion
}
