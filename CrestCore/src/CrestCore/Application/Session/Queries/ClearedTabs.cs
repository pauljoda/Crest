using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The open tabs `ClearCurrentTabs` would archive from a Space for the window
/// that asks, as the session stands now: every open tab, or with
/// `KeepsShownTab`, all but the tab the window shows there and the rest of
/// its split. Refused with `UnknownSpace` for a Space that is not there.
public sealed record ClearedTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, bool KeepsShownTab = false) : Query<RemovedTabs> {
    #region Actions - Answering

    internal override RemovedTabs Answer(CrestApp app) {
        var authority = app.Device.Workspace(WorkspaceId);
        var space = authority.Current.KnownSpace(SpaceId);
        var shown = authority.IssuingWindow(WindowId)?.Tab(space.Id);
        return new(ClearCurrentTabs.Cleared(BrowserTabCollection.Restore(space), shown, KeepsShownTab));
    }

    #endregion
}
