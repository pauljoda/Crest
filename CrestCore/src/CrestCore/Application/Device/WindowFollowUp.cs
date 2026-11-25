using CrestCore.Contracts;

namespace CrestCore.Application;

/// What a session command chose for the window that issued it to show next:
/// the Space to move to, the tab to show in each Space whose shown tab it
/// changed (null to show none), the tabs it dismissed, which that window's
/// history forgets, and the tabs other windows gave up to it. The device
/// applies it when the command commits; other windows are only repaired.
internal sealed class WindowFollowUp(Window? window) {
    #region Variables

    private readonly Dictionary<Guid, Guid?> tabs = [];
    private readonly List<(Guid SpaceId, Guid TabId)> dismissed = [];
    private readonly List<(Guid WindowId, Guid SpaceId, Guid TabId)> departed = [];

    /// The window that issued the command, as the command read it; null for a
    /// command issued without one.
    public Window? Window { get; } = window;
    public Guid? SpaceId { get; private set; }
    public IReadOnlyDictionary<Guid, Guid?> Tabs => tabs;
    public IReadOnlyList<(Guid SpaceId, Guid TabId)> Dismissed => dismissed;

    /// The tabs another window gave up to the window that issued the command,
    /// which that window's recent tabs forget.
    public IReadOnlyList<(Guid WindowId, Guid SpaceId, Guid TabId)> Departed => departed;

    #endregion

    #region Actions - Choosing

    public WindowFollowUp ShowSpace(Guid spaceId) {
        SpaceId = spaceId;
        return this;
    }

    /// Shows `tabId` in `spaceId`. Nothing is chosen when the window already
    /// shows it, so an unrelated command leaves the window as it was.
    public WindowFollowUp ShowTab(Guid spaceId, Guid? tabId) {
        if (Window?.Tab(spaceId) == tabId) tabs.Remove(spaceId);
        else tabs[spaceId] = tabId;
        return this;
    }

    public WindowFollowUp Dismiss(Guid spaceId, Guid tabId) {
        dismissed.Add((spaceId, tabId));
        return this;
    }

    /// Records that the window `windowId` gave `tabId` up in `spaceId`, which
    /// stays in the session for the window that issued the command.
    public WindowFollowUp Depart(Guid windowId, Guid spaceId, Guid tabId) {
        departed.Add((windowId, spaceId, tabId));
        return this;
    }

    /// The tab to show in `spaceId` after `tabId` leaves it: see
    /// `Window.DismissalFallback`, among `available` and, when given, only the
    /// `visible` tabs. Only a window that shows `tabId` there has one, and the
    /// dismissal is remembered for when the command commits.
    public Guid? FallbackAfterDismissing(Guid spaceId, Guid tabId, IReadOnlySet<Guid> available,
        IReadOnlySet<Guid>? visible = null) {
        if (Window is not { } shown || shown.Tab(spaceId) != tabId) return null;
        Dismiss(spaceId, tabId);
        return shown.DismissalFallback(spaceId, tabId, Among(available, visible));
    }

    /// The tab to show in `spaceId` after the tabs `tabIds` leave it together:
    /// see `Window.DismissalFallback`. Only a window that shows one of them
    /// there has one, and every one of them is remembered as dismissed for
    /// when the command commits, so none stays in the window's history.
    public Guid? FallbackAfterDismissing(Guid spaceId, IReadOnlySet<Guid> tabIds, IReadOnlySet<Guid> available,
        IReadOnlySet<Guid>? visible = null) {
        if (Window is not { } shown || shown.Tab(spaceId) is not { } tabId || !tabIds.Contains(tabId)) return null;
        foreach (var id in tabIds) Dismiss(spaceId, id);
        return shown.DismissalFallback(spaceId, tabIds, Among(available, visible));
    }

    /// The tabs the window's sidebar shows in `space`, with the rows its
    /// collapsed folders keep on screen; see `SpaceState.Visible`.
    public IReadOnlySet<Guid> Visible(SpaceState space) => space.Visible(Window?.KeptRows(space.Id));

    /// The tab the window shows in `after`, the Space once an edit took away
    /// the tab it showed there: `next` when the edit chose one, else the
    /// Space's fallback tab among those its sidebar shows, or none.
    public Guid? AfterShownLeft(SpaceState after, Guid? next) => next ?? after.FallbackTab(Window?.KeptRows(after.Id));

    private static IReadOnlySet<Guid> Among(IReadOnlySet<Guid> available, IReadOnlySet<Guid>? visible) =>
        visible is null ? available : available.Where(visible.Contains).ToHashSet();

    #endregion
}
