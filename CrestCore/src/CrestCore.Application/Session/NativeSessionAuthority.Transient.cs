using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// The Quick Window and Peek pages kept as tabs or archived. Transient
    /// presentations do not survive a restart, so the receipts live with the
    /// authority, and a late dismissal cannot archive a page already kept.
    private readonly HashSet<Guid> completedTransients = [];

    #endregion

    #region Actions - Transient pages

    /// Refuses a page whose promotion or archive already completed.
    internal void RequirePendingTransient(Guid? pageId) {
        if (pageId is { } value && completedTransients.Contains(value)) throw new Rejected(new TransientAlreadyCompleted(value));
    }

    /// Keeps the page as a new tab after the one the issuing window shows in
    /// the Space, which that window then shows. The tab takes the live page
    /// when the page lives in that Space and its engine can move it between
    /// windows.
    private SessionEdit PromotingTransientPage(SessionState basis, PromoteTransientPage intent, DateTimeOffset now, IIdSource ids,
        Pages? pages) {
        RequirePendingTransient(intent.PageId);
        var page = pages?.Transient(intent.PageId) is { } found && found.WorkspaceId == workspaceId
            ? found : throw new Rejected(new UnknownPage(intent.PageId));
        var source = Editable(basis, page.SpaceId);
        if (source.ProfileId != page.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, source.Id));
        var destination = Editable(basis, intent.SpaceId);
        var edited = BrowserTabCollection.Restore(destination);
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId));
        var tab = BrowserTab.Restore(NewTab(ids.Next(), new TabContent(intent.Address, View: null, Title: null, Symbol: null),
            intent.Placement, now));
        edited.InsertTab(tab, followUp.Window?.Tab(destination.Id) is { } shown ? edited.InsertionIndexAfter(shown) : null);
        followUp.ShowTab(destination.Id, tab.Id).ShowSpace(destination.Id);
        var adopts = page.MovesBetweenWindows && page.SpaceId == destination.Id && page.ProfileId == destination.ProfileId;
        return new(Replacing(basis, edited.Capture(destination)), SyncStaging.Creation, followUp,
            new([], null, new SessionTransientPromotion(page.Id, tab.Id, adopts)), Completes: page.Id);
    }

    /// Archives the page as a closed open tab of its Space.
    private SessionEdit ArchivingTransientPage(SessionState basis, ArchiveTransientPage intent, DateTimeOffset now, IIdSource ids,
        Pages? pages) {
        RequirePendingTransient(intent.PageId);
        var space = Editable(basis, intent.SpaceId);
        if (pages?.Transient(intent.PageId) is { } page
            && (page.WorkspaceId != workspaceId || page.SpaceId != space.Id || page.ProfileId != space.ProfileId))
            throw new Rejected(new PageProfileMismatch(page.Id, space.Id));
        var edited = BrowserTabCollection.Restore(space);
        edited.ArchiveTransient(NewTab(ids.Next(), new TabContent(intent.Address, View: null, intent.Title, Symbol: null),
            TabPlacement.Current, now), now);
        return new(Replacing(basis, edited.Capture(space)), SyncStaging.Edit, Completes: intent.PageId);
    }

    #endregion
}
