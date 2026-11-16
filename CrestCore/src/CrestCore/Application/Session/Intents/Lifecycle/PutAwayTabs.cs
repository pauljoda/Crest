using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Closes saved or pinned tabs together, as a folder's header closes the
/// loaded tabs it holds: each keeps its place and puts its page away, back at
/// its saved address when the app's preferences say so, as `CloseTab` closes
/// one. A window that showed one of them returns to the tab it showed before
/// outside them and their splits, so none of them comes back as the next
/// closes. A tab that is not saved or pinned, or that the Space no longer
/// holds, is passed over.
public sealed record PutAwayTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, IReadOnlyList<Guid> TabIds) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var closing = space.Tabs.Where(tab => TabIds.Contains(tab.Id) && tab.Placement.IsDurable).ToList();
        if (closing.Count == 0) return null;
        var edited = BrowserTabCollection.Restore(space);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shown = followUp.Window?.Tab(space.Id);
        var ids = closing.Select(tab => tab.Id).ToHashSet();
        var splits = closing.Select(tab => tab.SplitGroupId).OfType<Guid>().ToHashSet();
        var fallback = followUp.FallbackAfterDismissing(space.Id, ids, space.Tabs
            .Where(candidate => !ids.Contains(candidate.Id)
                && (candidate.SplitGroupId is not { } split || !splits.Contains(split)))
            .Select(candidate => candidate.Id).ToHashSet());
        var policy = workspace.ClosePolicy(turn.Basis);
        var selected = shown;
        List<SessionPagePutAway> putAways = [];
        List<SessionSavedImage> savedImages = [];
        foreach (var tab in closing) {
            var returns = policy == SavedTabClosePolicy.ReturnToSavedUrl && (tab.SavedUrl ?? tab.Url) is not null;
            if (returns && tab.ReturnRestoresImage)
                savedImages.Add(new(tab.Id, TabSavedImageChange.Restore, tab.SavedFaviconUrl));
            selected = edited.CloseDurable(tab.Id, selected, fallback, returns);
            putAways.Add(new(WindowId, space.Id, tab.Id, KeepsState: !returns));
        }
        followUp.ShowTab(space.Id, selected);
        var events = SessionTabEvents.None with { PutAways = putAways, SavedImages = savedImages };
        return new(turn.Basis.Replacing(edited.Capture(space)), SyncStaging.Creation, followUp, events);
    }

    #endregion
}
