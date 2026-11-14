using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Opens `Address` as a new open tab, `TabId`, and joins it to the split of
/// `TargetTabId` as `JoinSplit` does, copies included. The tab is called by
/// the link's host until its page reports a title. The window that asked
/// shows the new tab.
public sealed record OpenLinkInSplit(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid TargetTabId,
    string Address) : SessionIntent(WorkspaceId) {
    #region Static Variables

    /// The address a caller names that only asks whether a link may join the
    /// split, before it has one.
    public const string ProbeAddress = AddressResolution.AboutBlank;

    #endregion

    #region Actions - Session

    /// Opens the link as a new open tab and joins it to the target's split.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (turn.Basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == TabId)))
            throw new Rejected(new TabAlreadyExists(TabId));
        var edited = BrowserTabCollection.Restore(space);
        var opened = workspace.NewTab(TabId, new TabContent(Address, View: null, Title: null), TabPlacement.Current, turn.Now);
        edited.InsertTab(BrowserTab.Restore(opened), null);
        var joined = workspace.Joining(turn.Basis, space, edited, WindowId, TabId, TargetTabId, null, turn.Pages, turn.Now, turn.Ids);
        return joined with { Events = (joined.Events ?? SessionTabEvents.None).Opening(WindowId, space.Id, TabId) };
    }

    #endregion
}
