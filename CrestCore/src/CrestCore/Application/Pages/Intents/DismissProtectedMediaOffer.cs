using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person dismissed a page's offer to reload its document on another
/// engine for protected media. The page stays, and its document offers no
/// more.
public sealed record DismissProtectedMediaOffer(Guid PageId) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        if (pages.Hosted(PageId) is { } page) pages.Update(page, turn.Changes, () => page.TakeProtectedMediaOffer());
    }

    #endregion
}
