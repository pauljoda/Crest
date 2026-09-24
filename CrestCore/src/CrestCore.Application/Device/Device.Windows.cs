using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed partial class Device {
    #region Actions - Intents

    /// Runs one window intent, publishing what it changed to `changes`.
    public void Handle(WindowIntent intent, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(changes);
        switch (intent) {
            case OpenWindow opening: Open(opening, changes); break;
            case CloseWindow closing: Close(closing, changes); break;
            case ShowSpace showing: Show(showing, changes); break;
            case ShowTab showing: Show(showing, changes); break;
            case ResizeSplitColumns resizing: Resize(resizing, changes); break;
            case AdoptWindowRecords adoption: Adopt(adoption, changes); break;
            default: throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "The device does not handle this intent.");
        }
    }

    private void Open(OpenWindow intent, ChangeFeed changes) {
        var authority = Workspace(intent.WorkspaceId);
        var session = authority.Current;
        lock (gate) {
            if (open.TryGetValue(intent.WindowId, out var existing)) {
                changes.Publish(new WindowChanged(existing.State));
                return;
            }
            if (intent.Saved && intent.WorkspaceId != persistentWorkspace)
                throw new Rejected(new UnsavedWorkspace(intent.WorkspaceId));
            var window = intent.Saved && saved.TryGetValue(intent.WindowId, out var record)
                ? Window.Restoring(record, intent.WorkspaceId, intent.RestoresTabs)
                : intent.CopyingWindowId is { } copied && open.TryGetValue(copied, out var source) && source.WorkspaceId == intent.WorkspaceId
                    ? Window.Copying(source, intent.WindowId, intent.Saved)
                    : Window.Launching(intent.WindowId, intent.WorkspaceId, intent.Saved, session,
                        intent.WorkspaceId == persistentWorkspace ? legacyTabs : new Dictionary<Guid, Guid>());
            if (intent.ShowingSpaceId is { } showing && session.Spaces.Any(space => space.Id == showing)) window.MoveTo(showing);
            window.Repair(session);
            open[window.Id] = window;
            if (window.Saved) Record(window);
            changes.Publish(new WindowChanged(window.State));
        }
    }

    private void Close(CloseWindow intent, ChangeFeed changes) {
        lock (gate) {
            if (!open.Remove(intent.WindowId)) return;
        }
        changes.Publish(new WindowClosed(intent.WindowId));
    }

    private void Show(ShowSpace intent, ChangeFeed changes) {
        var window = Opened(intent.WindowId);
        var session = Workspace(window.WorkspaceId).Current;
        if (Available(session, intent.SpaceId) is not { } space || window.ShownSpaceId == space.Id) return;
        lock (gate) Publish(Changing([window], shown => shown.ShowSpace(space)), changes);
    }

    /// Showing a tab records its use first, as its own revision of the
    /// workspace, so cleanup never archives what a window just showed.
    private void Show(ShowTab intent, ChangeFeed changes) {
        var window = Opened(intent.WindowId);
        var authority = Workspace(window.WorkspaceId);
        if (Available(authority.Current, intent.SpaceId) is not { } space) return;
        if (intent.TabId is { } tabId) {
            if (space.Tabs.All(tab => tab.Id != tabId)) return;
            if (authority.Touch(intent.SpaceId, tabId, DateTimeOffset.UtcNow) is not { } touched) return;
            changes.Publish(new TabActivated(window.WorkspaceId, intent.SpaceId, tabId, touched.At, checked((long)touched.Revision)));
        }
        lock (gate) Publish(Changing([window], shown => shown.ShowTab(intent.SpaceId, intent.TabId)), changes);
    }

    private void Resize(ResizeSplitColumns intent, ChangeFeed changes) {
        var window = Opened(intent.WindowId);
        var session = Workspace(window.WorkspaceId).Current;
        if (Window.SplitShares(intent.Shares) is null) throw new Rejected(new InvalidSplitColumnShares());
        lock (gate) Publish(Changing([window], resized => {
            resized.Resize(intent.GroupId, intent.Shares);
            resized.Repair(session);
        }), changes);
    }

    private static void Publish(List<Change> published, ChangeFeed changes) {
        foreach (var change in published) changes.Publish(change);
    }

    #endregion

    #region Actions - Queries

    /// Whether a dragged tab may leave its window: the window still shows the
    /// Space the drag started in, with the profile it had and not being
    /// deleted, the Space is unlocked and holds the tab, and the drag carries
    /// that tab alone.
    public TearOffPermission Answer(CanTearOff question) {
        ArgumentNullException.ThrowIfNull(question);
        var window = Opened(question.WindowId);
        var authority = Workspace(window.WorkspaceId);
        var space = Available(authority.Current, question.SpaceId);
        if (space is null || space.ProfileId != question.ProfileId) return Refused(TearOffRefusal.SpaceChanged);
        if (authority.IsLocked(space)) return Refused(TearOffRefusal.SpaceLocked);
        if (space.Tabs.All(tab => tab.Id != question.TabId)) return Refused(TearOffRefusal.TabGone);
        if (question.DraggedTabs is { } dragged && (dragged.Count != 1 || dragged[0] != question.TabId))
            return Refused(TearOffRefusal.SeveralTabs);
        return new(Allowed: true, Reason: null);

        static TearOffPermission Refused(TearOffRefusal reason) => new(Allowed: false, reason);
    }

    #endregion

    #region Actions - Lookup

    private Window Opened(Guid windowId) {
        lock (gate) return open.TryGetValue(windowId, out var window) ? window : throw new Rejected(new WindowNotOpen(windowId));
    }

    private NativeSessionAuthority Workspace(Guid workspaceId) {
        lock (gate)
            return workspaces.TryGetValue(workspaceId, out var authority) ? authority : throw new Rejected(new UnknownWorkspace(workspaceId));
    }

    /// The Space a window may show: one the session holds that is not being deleted.
    private static SpaceState? Available(SessionState session, Guid spaceId) =>
        session.SpaceDeletions.Any(deletion => deletion.SpaceId == spaceId) ? null : session.Spaces.FirstOrDefault(space => space.Id == spaceId);

    #endregion
}
