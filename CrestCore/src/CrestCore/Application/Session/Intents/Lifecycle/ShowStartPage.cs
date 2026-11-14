using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Shows a Start Page in a Space: the window that asked shows the Space's first
/// open Start Page in no folder, or, when `OutsideSplits`, its first one in no
/// split; when the Space has none, a new one, `TabId`, opens after the tab the
/// window shows there. A window returning to a Space asks for one outside
/// splits, so it never lands on half of a split. When `JoinsFolder`, as for a
/// new tab the person asked for, a tab the window shows inside a folder has
/// the Start Page in that folder instead: the one it holds, or a new one at
/// its end, saved with a saved folder.
public sealed record ShowStartPage(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, bool OutsideSplits,
    bool JoinsFolder = false) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Shows the Space's first open Start Page in no folder, outside splits
    /// when asked, or opens one after the tab the window shows there; for a new
    /// tab, the Start Page of the folder that tab sits in. Showing the one it
    /// has records its use, as showing a tab does.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var edited = BrowserTabCollection.Restore(space);
        var shown = followUp.Window?.Tab(space.Id);
        var folder = JoinsFolder && shown is { } shownId ? space.Tabs.FirstOrDefault(tab => tab.Id == shownId)?.FolderId : null;
        var draft = space.Tabs.FirstOrDefault(tab => tab.IsStartPage && tab.FolderId == folder
            && (folder is not null || !tab.Placement.IsDurable) && (!OutsideSplits || edited.SplitMembers(tab.Id).Count < 2));
        if (draft is null)
            return new OpenTab(WorkspaceId, WindowId, space.Id, TabId,
                new TabContent(Address: null, View: null, Title: null), TabPlacement.Current,
                AfterTabId: shown, Shows: true, JoinsFolder) { SavesInSavedFolder = true }.Edit(workspace, turn);
        followUp.ShowTab(space.Id, draft.Id).ShowSpace(space.Id);
        var used = StoredSessionCodec.Date(StoredSessionCodec.Seconds(turn.Now));
        var tabs = space.Tabs.Select(tab => tab.Id == draft.Id ? tab with { LastActivatedAt = used } : tab);
        return new(turn.Basis.Replacing(space with { Tabs = [.. tabs] }),
            SyncStaging.TabUse, followUp);
    }

    #endregion
}
