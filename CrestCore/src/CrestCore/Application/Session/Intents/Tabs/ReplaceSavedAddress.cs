using CrestCore.Application;

namespace CrestCore.Contracts;

/// Makes the page a saved or pinned tab shows the one it belongs to, whose
/// title and image it keeps as its saved page's. A tab at its saved address
/// changes nothing. Refused with `NoSavedAddress` for a tab that belongs
/// nowhere.
public sealed record ReplaceSavedAddress(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        SessionSavedImage? saved = null;
        var edit = workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => {
            var tab = edited.Tab(TabId);
            var replaces = tab.State.IsAwayFromSavedAddress;
            tab.ReplaceSavedAddress();
            if (replaces) saved = new(TabId, TabSavedImageChange.Keep, tab.State.SavedFaviconUrl);
        });
        return saved is null ? edit : edit with { Events = SessionTabEvents.None with { SavedImages = [saved] } };
    }

    #endregion
}
