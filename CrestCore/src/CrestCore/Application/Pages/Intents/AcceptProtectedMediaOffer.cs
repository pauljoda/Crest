using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person accepted a page's offer to reload its document on the engine
/// that plays the protected media it asked for. The page moves there as an
/// automatic fallback would, honoring its before-unload decision first, and
/// its site opens there from then on. An offer for a document the page no
/// longer shows, or one the rules no longer allow, such as a site engine the
/// person chose or a choice never to switch made since, changes nothing but
/// the offer, which goes.
public sealed record AcceptProtectedMediaOffer(Guid PageId) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        if (pages.Hosted(PageId) is not { } page) return;
        Engine? offered = null;
        pages.Update(page, turn.Changes, () => offered = page.TakeProtectedMediaOffer());
        if (offered is not null && pages.Device.ProtectedMediaFallback.Switches
            && pages.ProtectedMediaFallback(page, turn) is { } fallback
            && ReferenceEquals(fallback.Engine, offered))
            pages.FallBack(page, fallback.Engine, fallback.Address, turn);
    }

    #endregion
}
