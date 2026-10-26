using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Opens a tab, `TabId`, showing `Content` in `Placement`'s section of a
/// Space. `AfterTabId` names the tab it opens from, and `Opening` says why it
/// opens: a new tab and a link go where the device's link preferences put
/// them, and a tab opened programmatically follows the last tab `OpenerId`
/// opened, else `AfterTabId`. A tab placed after another goes outside its
/// split. When `Shows`, the window that asked shows the tab and its Space.
/// Refused with `TabLimitReached` or `PinnedTabsFull` when the Space or the
/// section is full, and with `UnsupportedAddress` for an address a page cannot
/// load.
public sealed record OpenTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, TabContent Content, TabPlacement Placement,
    Guid? AfterTabId, bool Shows, TabOpening Opening, Guid? OpenerId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Opens the tab, which the issuing window shows when the intent asks.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (turn.Basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == TabId)))
            throw new Rejected(new TabAlreadyExists(TabId));
        var edited = BrowserTabCollection.Restore(space);
        var tab = BrowserTab.Restore(workspace.NewTab(TabId, Content, Placement, turn.Now));
        var origin = Opening.Origin(workspace, OpenerId, space, Placement, AfterTabId);
        edited.InsertTab(tab, Opening.PlacementUnder(workspace.LinkPreferences).InsertionIndex(edited, origin));
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (Shows) followUp.ShowTab(space.Id, tab.Id).ShowSpace(space.Id);
        return new(turn.Basis.Replacing(edited.Capture(space)), SyncStaging.Creation, followUp,
            Opened: Opening.Opened(OpenerId, tab.Id));
    }

    #endregion
}
