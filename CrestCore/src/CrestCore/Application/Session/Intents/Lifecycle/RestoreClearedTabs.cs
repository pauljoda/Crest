using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Takes back the clear `ClearId` that `ClearCurrentTabs` made in a Space:
/// each tab it archived that is still in the archive, and each Start Page it
/// let go, opens again where it stood, in its folder and split, which come
/// back as they were when the clear took them. Tabs opened since keep their
/// places. The window that asked shows the Space, on the tab it showed when
/// it cleared. Refused with `ClearedTabsGone` when the workspace no longer
/// remembers the clear, or none of its tabs is left to bring back.
public sealed record RestoreClearedTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid ClearId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Opens the tabs the clear archived again where they stood, and the
    /// issuing window shows the tab it showed when it cleared.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (workspace.RememberedClear(ClearId) is not { } mark || mark.Before.Id != space.Id)
            throw new Rejected(new ClearedTabsGone(ClearId));
        var open = turn.Basis.Spaces.SelectMany(candidate => candidate.Tabs).Select(tab => tab.Id).ToHashSet();
        TabState[] returning = [.. mark.Before.Tabs.Where(tab => mark.TabIds.Contains(tab.Id) && !open.Contains(tab.Id))
            .Select(tab => Returning(tab, space)).OfType<TabState>()];
        if (returning.Length == 0) throw new Rejected(new ClearedTabsGone(ClearId));
        var ids = returning.Select(tab => tab.Id).ToHashSet();
        var remaining = space with { ArchivedTabs = [.. space.ArchivedTabs.Where(archived => !ids.Contains(archived.Tab.Id))] };
        var edited = BrowserTabCollection.Restore(remaining);
        edited.RestoreCleared(mark.Before, returning, turn.Now);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (mark.Shown is { } shown && edited.Tabs.Any(tab => tab.Id == shown)) followUp.ShowTab(space.Id, shown);
        followUp.ShowSpace(space.Id);
        return new(turn.Basis.Replacing(edited.Capture(remaining)), SyncStaging.Creation, followUp,
            SessionTabEvents.None.Opening(WindowId, space.Id, [.. returning.Select(tab => tab.Id)]));
    }

    /// What `cleared`, as the Space held it before the clear, opens as: its
    /// latest record in `space`'s archive, back in the folder and split it sat
    /// in, or itself for a Start Page, which the clear never archived. Null for
    /// a tab no longer in the archive.
    private static TabState? Returning(TabState cleared, SpaceState space) =>
        space.ArchivedTabs.LastOrDefault(archived => archived.Tab.Id == cleared.Id) is { } archived
            ? archived.Tab with { Placement = cleared.Placement, FolderId = cleared.FolderId, SplitGroupId = cleared.SplitGroupId }
            : cleared.IsStartPage ? cleared : null;

    #endregion
}
