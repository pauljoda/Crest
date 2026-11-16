using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a window can switch between in the Space it shows: the tabs it showed
/// there since it opened whose pages are loaded or that show a native view, a
/// split as one item, the shown item first whether or not its page is (see
/// `Device.RecentItems`). Items are in memory only, so a window that has shown
/// nothing else lists its shown tab and the Space's loaded tab used last. A
/// Space with Sub-Spaces lists the loaded tabs of its whole group, each item
/// naming its Space.
public sealed record RecentTabs(Guid WindowId) : Query<RecentTabList> {
    #region Actions - Answering

    /// The items the window can switch between in the Space it shows.
    internal override RecentTabList Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var session = app.Device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        lock (app.Device.Gate) spaceId = window.ShownSpaceId;
        return new(Device.Available(session, spaceId) is { } space ? app.Device.RecentItems(window, space, app.Pages) : []);
    }

    #endregion
}
