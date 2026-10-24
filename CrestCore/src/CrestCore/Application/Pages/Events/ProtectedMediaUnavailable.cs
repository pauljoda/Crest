using CrestCore.Application;

namespace CrestCore.Contracts;

/// The document asked for an unsupported key system. Falls back once per
/// document as the device's `ProtectedMediaFallback` says: a move that honors
/// its before-unload decision first, an offer to move, or nothing.
public sealed record ProtectedMediaUnavailable(Guid PageId, KeySystem KeySystem) : PageEvent(PageId) {
    #region Actions - Pages

    /// An explicit site choice wins over any fallback. A page that moved once
    /// never bounces back because the other engine also probes.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (pages.ProtectedMediaFallback(page, turn) is { } fallback)
            pages.Device.ProtectedMediaFallback.FallBack(pages, page, fallback.Engine, fallback.Address, turn);
    }

    #endregion
}
