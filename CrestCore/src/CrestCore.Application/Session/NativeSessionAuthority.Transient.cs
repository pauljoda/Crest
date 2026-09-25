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

    /// Keeps the page as a new tab at the address it shows, after the one the
    /// issuing window shows in the Space, which that window then shows. The
    /// tab takes the live page when the page lives in that Space and its
    /// engine can move it between windows.
    private SessionEdit PromotingTransientPage(SessionState basis, PromoteTransientPage intent, DateTimeOffset now, IIdSource ids,
        Pages? pages) {
        RequirePendingTransient(intent.PageId);
        var page = Known(intent.PageId, pages);
        var source = Editable(basis, page.SpaceId);
        if (source.ProfileId != page.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, source.Id));
        var destination = Editable(basis, intent.SpaceId);
        var edited = BrowserTabCollection.Restore(destination);
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId));
        var tab = BrowserTab.Restore(NewTab(ids.Next(), new TabContent(page.Address, View: null, page.Title, Symbol: null),
            intent.Placement, now));
        edited.InsertTab(tab, followUp.Window?.Tab(destination.Id) is { } shown ? edited.InsertionIndexAfter(shown) : null);
        followUp.ShowTab(destination.Id, tab.Id).ShowSpace(destination.Id);
        var adopts = page.MovesBetweenWindows && page.SpaceId == destination.Id && page.ProfileId == destination.ProfileId;
        return new(Replacing(basis, edited.Capture(destination)), SyncStaging.Creation, followUp,
            new([], null, new SessionTransientPromotion(page.Id, tab.Id, adopts)), Completes: page.Id);
    }

    /// Archives the page as a closed open tab of its Space, at the address and
    /// title it shows, or showed last when it is already gone.
    private SessionEdit ArchivingTransientPage(SessionState basis, ArchiveTransientPage intent, DateTimeOffset now, IIdSource ids,
        Pages? pages) {
        RequirePendingTransient(intent.PageId);
        var space = Editable(basis, intent.SpaceId);
        var page = Known(intent.PageId, pages);
        if (page.SpaceId != space.Id || page.ProfileId != space.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, space.Id));
        var edited = BrowserTabCollection.Restore(space);
        edited.ArchiveTransient(NewTab(ids.Next(), new TabContent(page.Address, View: null, page.Title, Symbol: null),
            TabPlacement.Current, now), now);
        return new(Replacing(basis, edited.Capture(space)), SyncStaging.Edit, Completes: intent.PageId);
    }

    /// The Quick Window or Peek page of this workspace that `pageId` names,
    /// open or remembered. Throws `Rejected` when the device knows no such
    /// page.
    private TransientPage Known(Guid pageId, Pages? pages) =>
        pages?.Transient(pageId) is { } page && page.WorkspaceId == workspaceId ? page : throw new Rejected(new UnknownPage(pageId));

    #endregion
}
