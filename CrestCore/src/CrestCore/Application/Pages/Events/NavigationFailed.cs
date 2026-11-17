using CrestCore.Application;

namespace CrestCore.Contracts;

/// A page's navigation failed as `Failure` describes, so the document it was
/// loading records nothing, and the page shows the failure until another
/// navigation begins. A site the person typed without a scheme, which Crest
/// tried over https, loads over http instead when https couldn't reach it.
public sealed record NavigationFailed(Guid PageId, PageFailure Failure) : PageEvent(PageId) {
    #region Actions - Pages

    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (Failure.Error.FallsBackToHttp && page.Phase.HoldsEnginePage && pages.Device.HttpFallbacks.Take(Failure.Url) is { } http) {
            try {
                Navigate.Load(pages, turn, page.Id, (_, _) => http);
                return;
            } catch (Rejected) {
                // A page that can't load now, as in a Space locked since,
                // shows the failure it had.
            }
        }
        pages.Update(page, turn.Changes, () => page.Fail(Failure));
    }

    #endregion
}
