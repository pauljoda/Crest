using CrestCore.Application;

namespace CrestCore.Contracts;

/// The app or desktop regained focus while showing this video source.
public sealed record FocusPictureInPictureSource(Guid PageId) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        pages.EndPictureInPicture(page, pages.IsShown(page), turn.Issue);
    }

    #endregion
}
