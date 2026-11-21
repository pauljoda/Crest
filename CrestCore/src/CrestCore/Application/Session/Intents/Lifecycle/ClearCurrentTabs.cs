using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Archives the open tabs of a Space and keeps its saved and pinned tabs. With
/// `KeepsShownTab`, the open tab the window that asked shows there stays too,
/// with the rest of its split. The window that asked shows the tab it showed
/// there when that tab stays, or the one its Space falls back to. Refused with
/// `NoCurrentTabs` when the Space has no open tab to archive.
public sealed record ClearCurrentTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, bool KeepsShownTab = false)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Archives the Space's open tabs, but for the shown one when it is kept.
    /// The issuing window shows the tab it showed there when that tab stays,
    /// or the one the Space falls back to.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shown = followUp.Window?.Tab(space.Id);
        var kept = KeepsShownTab && shown is { } tab && edited.Tabs.Any(candidate => candidate.Id == tab)
            ? edited.SplitMembers(tab).Select(member => member.Id).ToHashSet()
            : [];
        var open = edited.Tabs.Where(tab => !tab.Placement.IsDurable && !kept.Contains(tab.Id)).Select(tab => tab.Id).ToArray();
        if (open.Length == 0) throw new Rejected(new NoCurrentTabs(space.Id));
        var selected = edited.DismissTabs(open, shown, null, turn.Now, ArchiveReason.Closed, ensureSelection: true);
        edited.PruneSplitMetadata();
        followUp.ShowTab(space.Id, selected);
        return new(turn.Basis.Replacing(edited.Capture(space)), SyncStaging.Creation, followUp);
    }

    #endregion
}
