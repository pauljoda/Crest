using CrestCore.Application;

namespace CrestCore.Contracts;

/// Returns a saved or pinned tab to the address it belongs to, which its page
/// then loads, wearing its saved page's title and image again. A tab already
/// there changes nothing, and its page may still load it. Refused with
/// `NoSavedAddress` for a tab that belongs nowhere.
public sealed record ReturnToSavedAddress(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        SessionSavedImage? saved = null;
        var edit = workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => {
            var tab = edited.Tab(TabId);
            var restoresImage = tab.State.ReturnRestoresImage;
            tab.ReturnToSavedAddress();
            if (restoresImage) saved = new(TabId, TabSavedImageChange.Restore, tab.State.SavedFaviconUrl);
        });
        return saved is null ? edit : edit with { Events = SessionTabEvents.None with { SavedImages = [saved] } };
    }

    #endregion
}
