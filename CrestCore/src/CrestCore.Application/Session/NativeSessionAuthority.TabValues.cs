using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Tab values

    private SessionEdit RenamingTab(SessionState basis, RenameTab intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.Tab(intent.TabId).Rename(intent.Title, now));

    /// A tab that pulls its page's favicon wears the image the issuer offered,
    /// and any other choice drops its image. The assignment is published even
    /// when the choice changes nothing else, so a favicon pulled again from the
    /// same page replaces the image the tab wears.
    private SessionEdit ChoosingTabIcon(SessionState basis, ChooseTabIcon intent) {
        var adopts = false;
        var edit = Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited =>
            adopts = edited.Tab(intent.TabId).ChooseIcon(intent.Mode, intent.Emoji, intent.Accent));
        return edit with { Events = new([], new SessionFaviconUpdate(intent.TabId, adopts)) };
    }

    private SessionEdit ReplacingSavedAddress(SessionState basis, ReplaceSavedAddress intent) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.Tab(intent.TabId).ReplaceSavedAddress());

    private SessionEdit ReturningToSavedAddress(SessionState basis, ReturnToSavedAddress intent) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.Tab(intent.TabId).ReturnToSavedAddress());

    private SessionEdit KeepingPageLoaded(SessionState basis, KeepPageLoaded intent) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.Tab(intent.TabId).SetResidency(intent.Keeps));

    #endregion
}
