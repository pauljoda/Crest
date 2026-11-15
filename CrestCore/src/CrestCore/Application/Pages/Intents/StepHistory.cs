using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a page `Offset` entries through its back and forward history: -1
/// goes back, 1 goes forward. Going back from a failed navigation first
/// leaves the failure: a failure over the document the page still shows
/// returns to that document, and one that replaced its document goes back
/// past it. A page whose history has no entry there stays, except the first
/// page of a tab another tab opened going back: once its document agrees to
/// go, that tab closes as its close button would, and its window shows the
/// tab that opened it (see `CloseTab`). Refused when the page is not open, or
/// while another close is being prepared.
public sealed record StepHistory(Guid PageId, int Offset) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        if (Offset < 0 && page.Live.Failure is { } failure) {
            pages.Update(page, turn.Changes, page.LeaveFailure);
            if (!failure.ReplacedDocument) return;
        }
        if (page.History.Step(Offset) is { } entry) pages.Traverse(page, entry.Id, turn);
        else if (Offset < 0 && page.OpenerTabId is { } opener) turn.Closing.CloseOwner(page, opener, turn);
    }

    #endregion
}
