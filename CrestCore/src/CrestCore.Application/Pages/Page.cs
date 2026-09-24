using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One page this device hosts: its owner, the window that hosts it, the engine
/// that hosts it, where it stands there and its live state. Its engine page
/// lives in the profile of the Space it opened in, so the page only ever moves
/// between Spaces of that profile.
internal sealed class Page {
    #region Variables

    public Guid Id { get; }
    public Engine Engine { get; }
    public Guid ProfileId { get; }

    public Guid WorkspaceId { get; private set; }
    public Guid SpaceId { get; private set; }

    /// The tab that owns the page, or null for a Quick Window or Peek page.
    public Guid? TabId { get; private set; }

    /// The window that hosts the page. A window that shares its pages with
    /// others shows this page without owning it.
    public Guid WindowId { get; private set; }

    public PagePhase Phase { get; private set; } = PagePhase.Opening;

    public PageState State => new(Id, WorkspaceId, SpaceId, TabId, Engine.Kind, Phase, Live);

    /// What rules and views read of the page now: what its engine last showed,
    /// and why its latest navigation failed. A failure over the document the
    /// page still shows can be left for that document, so the page can go back
    /// even when its engine's history cannot.
    public PageLiveState Live => new(shown.Url, shown.PendingUrl, shown.Title, shown.IsLoading,
        shown.CanGoBack || failure is { ReplacedDocument: false } && shown.Url is not null, shown.CanGoForward, shown.Security,
        failure, shown.Media);

    /// The icon the engine last reported for the document the page shows.
    public PageIcon? Icon { get; private set; }

    /// What the page's engine last reported it shows, with the address the
    /// core asked it to load since.
    private PageSnapshot shown = PageSnapshot.Blank;

    /// Why the page's latest navigation failed, until another commits a new
    /// document or the page is asked to load or leave the failure.
    private PageFailure? failure;

    /// The address of the page the document shows, as it last committed or
    /// was recorded.
    private string? documentUrl;

    /// The document's navigation is recorded, or ended with nothing to record.
    private bool isRecorded;

    #endregion

    #region Constructors

    public Page(Guid id, Engine engine, Guid profileId, Guid workspaceId, Guid spaceId, Guid? tabId, Guid windowId) {
        Id = id;
        Engine = engine;
        ProfileId = profileId;
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
        WindowId = windowId;
    }

    #endregion

    #region Actions - Lifecycle

    /// Moves the page to `next` when it may follow the phase the page is in,
    /// and answers whether it did.
    public bool Enter(PagePhase next) {
        if (!next.Follows(Phase)) return false;
        Phase = next;
        return true;
    }

    /// Gives the page a new owner in a Space of its profile, hosted by `windowId`.
    public void Move(Guid workspaceId, Guid spaceId, Guid? tabId, Guid windowId) {
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
        WindowId = windowId;
    }

    #endregion

    #region Actions - Navigation

    /// A navigation took effect at `url`. A new document begins a record of
    /// its own, without the icon of the one it replaced. A move within the
    /// document begins one only when it reaches another page: a fragment is
    /// part of the page it names, and the document keeps its icon.
    public void Commit(string url, bool sameDocument) {
        if (!sameDocument) failure = null;
        if (sameDocument && documentUrl is { } shown && new WebAddress(shown).IsSamePage(new WebAddress(url))) return;
        documentUrl = url;
        isRecorded = false;
        if (!sameDocument) Icon = null;
    }

    /// A navigation finished at `url`. Answers whether it is the first finish
    /// of its document, which the core records; a later one records nothing.
    public bool Finish(string url) {
        if (isRecorded) return false;
        documentUrl = url;
        isRecorded = true;
        return true;
    }

    /// A navigation failed as `reason` describes, so the document it was
    /// loading records nothing, and the page shows the failure in place of
    /// where it was heading.
    public void Fail(PageFailure reason) {
        isRecorded = true;
        failure = reason;
        shown = shown with { PendingUrl = null };
    }

    /// The page is asked to load `url`, and shows it heading there at once.
    public void Load(string url) {
        failure = null;
        shown = shown with { PendingUrl = url };
    }

    /// The person left the page's failure for the document behind it.
    public void LeaveFailure() => failure = null;

    /// The engine reported what the page shows now.
    public void Show(PageSnapshot snapshot) => shown = snapshot;

    /// The engine reported an icon for the document. Answers whether its tab
    /// may wear it now: the page has a tab and the document is recorded, so
    /// the tab shows it. Otherwise the record adopts it.
    public bool ShowIcon(PageIcon icon) {
        Icon = icon;
        return TabId is not null && isRecorded;
    }

    #endregion
}
