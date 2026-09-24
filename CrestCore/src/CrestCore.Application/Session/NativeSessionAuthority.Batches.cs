using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// A selection intent's work: the Space its window shows, that Space's
    /// organization the intent edits, the selection resolved there, and what
    /// the window shows next.
    private sealed record SelectionEdit(SpaceState Space, BrowserTabCollection Edited, SelectedTabs Selected, WindowFollowUp FollowUp) {
        #region Variables

        /// The tab the window shows in the Space, or null for none.
        public Guid? Shown => FollowUp.Window?.Tab(Space.Id);

        #endregion

        #region Actions - Following

        /// The tab the window shows once the edit takes its shown tab away: the
        /// one it showed before, among the tabs the selection leaves; null when
        /// the shown tab stays or nothing qualifies.
        public Guid? Fallback() => Shown is { } shown && Selected.Holds(shown)
            ? FollowUp.FallbackAfterDismissing(Space.Id, shown, Space.Tabs.Select(tab => tab.Id).Where(id => !Selected.Holds(id)).ToHashSet())
            : null;

        /// The session with the edited organization, staged as `staging`, with
        /// what the window shows next and what the edit did that the states
        /// cannot tell. Split metadata no tab uses goes with the edit.
        public SessionEdit Result(SessionState basis, SyncStaging staging, SessionTabEvents? events = null,
            params SpaceState[] alsoEdited) {
            Edited.PruneSplitMetadata();
            return new(Replacing(basis, [Edited.Capture(Space), .. alsoEdited]), staging, FollowUp, events);
        }

        #endregion
    }

    #endregion

    #region Actions - Selections

    /// The work of an intent on a selection made in `windowId`'s sidebar: the
    /// Space must be the one the window shows, and the selection must hold
    /// what the window saw, or it is refused with `SelectionChanged`.
    private SelectionEdit Selecting(SessionState basis, Guid windowId, Guid spaceId, TabSelection selection) {
        var followUp = new WindowFollowUp(IssuingWindow(windowId));
        if (followUp.Window?.ShownSpaceId != spaceId) throw new Rejected(new SelectionChanged());
        var space = Editable(basis, spaceId);
        var edited = BrowserTabCollection.Restore(space);
        return new(space, edited, edited.Select(selection), followUp);
    }

    /// Copies of tabs start from where their sources' pages are now, preferring
    /// the pages `windowId` shows; see `StartFromSourcePage`. Answers what the
    /// copies publish.
    private SessionTabEvents StartingCopies(SelectionEdit batch, IReadOnlyList<(Guid Source, Guid Copy)> copies, Guid windowId,
        Pages? pages) {
        foreach (var (source, copy) in copies) StartFromSourcePage(batch.Edited.Tab(copy), source, windowId, pages);
        return new([.. copies.Select(pair => new SessionTabCopy(pair.Source, pair.Copy))], null);
    }

    #endregion

    #region Actions - Batches

    private SessionEdit ClosingTabs(SessionState basis, CloseTabs intent, DateTimeOffset now) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        batch.FollowUp.ShowTab(batch.Space.Id, batch.Edited.CloseSelected(batch.Selected, batch.Shown, batch.Fallback(), now));
        return batch.Result(basis, SyncStaging.Batch);
    }

    private SessionEdit DeletingTabs(SessionState basis, DeleteTabs intent, DateTimeOffset now) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        batch.FollowUp.ShowTab(batch.Space.Id, batch.Edited.DeleteSelected(batch.Selected, batch.Shown, batch.Fallback(), now));
        return batch.Result(basis, SyncStaging.BatchDeletion);
    }

    private SessionEdit DuplicatingTabs(SessionState basis, DuplicateTabs intent, DateTimeOffset now, IIdSource ids, Pages? pages) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        var copies = batch.Edited.DuplicateSelected(batch.Selected, ids, now);
        return batch.Result(basis, SyncStaging.Batch, StartingCopies(batch, copies, intent.WindowId, pages));
    }

    private SessionEdit SplittingTabs(SessionState basis, SplitTabs intent, DateTimeOffset now, IIdSource ids, Pages? pages) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        var (shown, copies) = batch.Edited.SplitSelected(batch.Selected, intent.TargetTabId, intent.Index, batch.Shown, ids, now);
        batch.FollowUp.ShowTab(batch.Space.Id, shown);
        return batch.Result(basis, SyncStaging.Batch, StartingCopies(batch, copies, intent.WindowId, pages));
    }

    private SessionEdit SeparatingSplits(SessionState basis, SeparateSplits intent, DateTimeOffset now) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        batch.Edited.SeparateSelected(batch.Selected, now);
        return batch.Result(basis, SyncStaging.Batch);
    }

    private SessionEdit KeepingTabsLoaded(SessionState basis, KeepTabsLoaded intent) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        batch.Edited.KeepSelectedLoaded(batch.Selected, intent.Keeps);
        return batch.Result(basis, SyncStaging.Batch);
    }

    /// The window gives up its shown tab when it moved, and moves to the
    /// destination when the intent follows the tabs there.
    private SessionEdit MovingTabsToSpace(SessionState basis, MoveTabsToSpace intent, DateTimeOffset now) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        if (intent.DestinationSpaceId == intent.SpaceId) throw new Rejected(new AlreadyInSpace(intent.SpaceId));
        var destination = Editable(basis, intent.DestinationSpaceId);
        var receiving = BrowserTabCollection.Restore(destination);
        var (shown, shownThere) = batch.Edited.MoveSelected(batch.Selected, receiving, batch.Shown, batch.Fallback(),
            batch.FollowUp.Window?.Tab(destination.Id), intent.Follows, now);
        receiving.PruneSplitMetadata();
        batch.FollowUp.ShowTab(batch.Space.Id, shown).ShowTab(destination.Id, shownThere);
        if (intent.Follows) batch.FollowUp.ShowSpace(destination.Id);
        return batch.Result(basis, SyncStaging.Batch, alsoEdited: receiving.Capture(destination));
    }

    private SessionEdit FoldingTabs(SessionState basis, FolderTabs intent, DateTimeOffset now, IIdSource ids) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        batch.Edited.FolderSelected(batch.Selected, intent.Placement, NewFolderTitle, FolderState.DefaultColor, ids, now);
        return batch.Result(basis, SyncStaging.Batch);
    }

    private SessionEdit FoldingTabsAround(SessionState basis, FolderTabsAround intent, DateTimeOffset now, IIdSource ids) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        batch.Edited.FolderSelectedAround(batch.Selected, intent.TabId, NewFolderTitle, FolderState.DefaultColor, ids, now);
        return batch.Result(basis, SyncStaging.Batch);
    }

    #endregion
}
