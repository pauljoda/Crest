using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// A lift resolved in the Space the window shows: the selection's work, and
    /// the tab it moves alone when it is one tab.
    private sealed record Lift(SelectionEdit Work, BrowserTab? Alone) {
        #region Variables

        /// Whether the lift holds only pinned tabs.
        public bool PinsOnly => !Work.Selected.HoldsFolders && Work.Selected.Members.All(tab => tab.Placement == TabPlacement.Pinned);

        #endregion
    }

    #endregion

    #region Actions - Drops

    /// Throws the rule that refuses the lift itself, whatever it drops on: the
    /// window no longer shows the Space or the selection changed, the Space
    /// takes no edits, or pinned tabs lift with others.
    internal void CheckLift(Guid windowId, Guid spaceId, TabSelection selection) {
        ArgumentNullException.ThrowIfNull(selection);
        lock (Gate) _ = Lifting(IntentBasis(), windowId, spaceId, selection);
    }

    /// The edit a drop commits, which is the one place that decides it: a lift
    /// of one tab moves that tab alone and leaves its split, as dragging a tab
    /// does; any other lift is a selection the batch intents act on whole.
    private SessionIntent Committed(SidebarDrop drop, SessionState basis, IIdSource ids) {
        var lift = Lifting(basis, drop.WindowId, drop.SpaceId, drop.Selection);
        return (drop, lift.Alone) switch {
            (DropIntoList into, { }) when into.Section.HoldsFolders => new FileTabs(drop.WorkspaceId, drop.WindowId, drop.SpaceId,
                drop.Selection, into.Section, into.FolderId, into.BeforeTabId, into.BeforeFolderId, LeavesSplits: true),
            (DropIntoList into, { } tab) => new MoveTab(drop.WorkspaceId, drop.SpaceId, tab.Id, into.Section, into.FolderId, into.BeforeTabId,
                LeavesSplit: true),
            (DropIntoList into, null) => into.Section.HoldsFolders || lift.PinsOnly
                ? new FileTabs(drop.WorkspaceId, drop.WindowId, drop.SpaceId, drop.Selection, into.Section, into.FolderId, into.BeforeTabId,
                    into.BeforeFolderId, LeavesSplits: false)
                : throw new Rejected(new PinsOneTabAtATime()),
            (DropOnSpace onto, { } tab) => new MoveTabToSpace(drop.WorkspaceId, drop.WindowId, drop.SpaceId, tab.Id, onto.DestinationSpaceId,
                Placement: null, FolderId: null, BeforeTabId: null, onto.Follows),
            (DropOnSpace onto, null) => lift.PinsOnly
                ? throw new Rejected(new PinnedTabsStayPut())
                : new MoveTabsToSpace(drop.WorkspaceId, drop.WindowId, drop.SpaceId, drop.Selection, onto.DestinationSpaceId, onto.Follows),
            (DropIntoSplit into, { } tab) => new JoinSplit(drop.WorkspaceId, drop.WindowId, drop.SpaceId, tab.Id, into.TargetTabId, into.Index),
            (DropIntoSplit into, null) => lift.PinsOnly
                ? throw new Rejected(new PinnedTabsStayPut())
                : new SplitTabs(drop.WorkspaceId, drop.WindowId, drop.SpaceId, drop.Selection, into.TargetTabId, into.Index),
            (DropAroundTab around, { } tab) => FoldsAround(lift.Work.Edited, around.TabId, tab.Id)
                ? new CreateFolder(drop.WorkspaceId, drop.SpaceId, ids.Next(), TabPlacement.Current, ParentId: null, Title: null,
                    FolderState.DefaultColor, FolderState.DefaultSymbol, [around.TabId, tab.Id], LeavesSplits: true)
                : throw new Rejected(new InvalidFolderPlacement()),
            (DropAroundTab around, null) => new FolderTabsAround(drop.WorkspaceId, drop.WindowId, drop.SpaceId, drop.Selection, around.TabId),
            _ => throw new ArgumentOutOfRangeException(nameof(drop), drop.GetType().Name, "The session does not commit this drop.")
        };
    }

    /// The lift of `selection` from `windowId`'s sidebar, resolved in the Space
    /// it shows, which pinned tabs never leave with others.
    private Lift Lifting(SessionState basis, Guid windowId, Guid spaceId, TabSelection selection) {
        var work = Selecting(basis, windowId, spaceId, selection);
        var alone = work.Selected.Roots is [{ IsFolder: false } root] ? work.Edited.Tab(root.Id) : null;
        var members = work.Selected.Members;
        if (alone is null && members.Any(tab => tab.Placement == TabPlacement.Pinned)
            && (work.Selected.HoldsFolders || members.Any(tab => tab.Placement != TabPlacement.Pinned)))
            throw new Rejected(new PinnedTabsDragAlone());
        return new(work, alone);
    }

    /// Whether a new folder may be made around the open tab `targetId` for
    /// `tabId`: it is an open tab at the top level, in no split, not a Start
    /// Page, and not the tab itself.
    private static bool FoldsAround(BrowserTabCollection organization, Guid targetId, Guid tabId) {
        var target = organization.Tab(targetId);
        return targetId != tabId && !target.Placement.IsDurable && target.FolderId is null && target.SplitGroupId is null
            && !target.Content.IsStartPage;
    }

    #endregion
}
