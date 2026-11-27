using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Closes a tab the way its section closes one: an open tab is archived, and
/// a saved or pinned tab keeps its place and only puts its page away, back at
/// its saved address when the app's preferences say so for its section. A window that showed
/// the tab shows `ReturnTabId` next while the Space holds it, as a tab going
/// back past its first page returns to the tab that opened it, and otherwise
/// returns to the tab it showed before, or to the tab beside it in the
/// sidebar when none it showed before is left. Refused with `LastStartPage` for the
/// Start Page when it is its Space's only tab, which leaves only the window
/// to close.
public sealed record CloseTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid? ReturnTabId = null)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Closes the tab the way its section closes one: a saved or pinned tab
    /// puts its page away, and an open tab is archived. A window that showed
    /// the tab returns to `ReturnTabId` or to the one it showed before; one
    /// that put a saved or pinned tab away skips its split, whose other
    /// members would present it again. A page put away keeps what brings it
    /// back unless the tab returns to its saved address, and the window that
    /// asked lets it go. A tab returning from another page wears its saved
    /// page's image again.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var tab = edited.Tab(TabId);
        var action = TabDismissalAction.Of(tab.Placement, tab.Content.IsStartPage, space.Tabs.Count);
        if (action.ClosesWindow) throw new Rejected(new LastStartPage(tab.Id));
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shown = followUp.Window?.Tab(space.Id);
        Guid? selected;
        SessionTabEvents? events = null;
        if (action.KeepsTab) {
            var group = tab.SplitGroupId;
            var fallback = Fallback(followUp, space, space.Tabs
                .Where(candidate => candidate.Id != tab.Id && (group is null || candidate.SplitGroupId != group))
                .Select(candidate => candidate.Id).ToHashSet());
            var returns = workspace.ClosePolicy(turn.Basis, tab.Placement) == SavedTabClosePolicy.ReturnToSavedUrl
                && (tab.SavedUrl ?? tab.Url) is not null;
            var restoresImage = returns && tab.State.ReturnRestoresImage;
            selected = edited.CloseDurable(tab.Id, shown, fallback, returns);
            events = SessionTabEvents.None with {
                PutAways = [new(WindowId, space.Id, tab.Id, KeepsState: !returns)],
                SavedImages = restoresImage ? [new(tab.Id, TabSavedImageChange.Restore, tab.State.SavedFaviconUrl)] : null
            };
        } else {
            var fallback = Fallback(followUp, space, space.Tabs.Select(candidate => candidate.Id).ToHashSet());
            selected = edited.DismissTabs([tab.Id], shown, fallback, turn.Now, ArchiveReason.Closed, ensureSelection: false);
            edited.PruneSplitMetadata();
        }
        followUp.ShowTab(space.Id, selected);
        return new(turn.Basis.Replacing(edited.Capture(space)), SyncStaging.Creation, followUp, events);
    }

    /// The tab a window that showed the closed tab shows next among
    /// `available`: `ReturnTabId` when it is one, or else the one the window
    /// showed before, or with none left, the one beside it in the sidebar.
    /// None for a window that did not show it.
    private Guid? Fallback(WindowFollowUp followUp, SpaceState space, IReadOnlySet<Guid> available) {
        var before = followUp.FallbackAfterDismissing(space.Id, TabId, available);
        if (followUp.Window?.Tab(space.Id) != TabId) return before;
        return ReturnTabId is { } returning && returning != TabId && available.Contains(returning)
            ? returning
            : before ?? space.Neighbor(TabId, available);
    }

    #endregion
}
