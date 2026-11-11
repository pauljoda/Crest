using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows the tab of the window's Space used last while the window shows none
/// there, as a phone window does when it launches, recording its use as
/// `ShowTab` does. A split shows the page used last. Publishes nothing when
/// the window already shows a tab, or the Space has none to show.
public sealed record ShowLastUsedTab(Guid WindowId) : WindowIntent {
    #region Actions - Device

    /// Shows the Space's tab used last the way `ShowTab` does. The window is
    /// read under the device lock and the session asked about the Space's
    /// lock outside it, since nothing calls on a session while it is held.
    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var session = device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        bool showsNone;
        lock (device.Gate) {
            spaceId = window.ShownSpaceId;
            showsNone = window.Tab(spaceId) is null;
        }
        if (!showsNone || Device.Available(session, spaceId) is not { } space
            || device.LastUsed(window, space) is not { } last) return;
        new ShowTab(WindowId, spaceId, last.FocusedTabId).Apply(device, turn);
    }

    #endregion
}
