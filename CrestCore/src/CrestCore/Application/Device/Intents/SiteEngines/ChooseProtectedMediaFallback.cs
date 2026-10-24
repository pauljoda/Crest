using CrestCore.Application;

namespace CrestCore.Contracts;

/// Chooses what pages on this device do from now on when their engine cannot
/// play the protected media a document asks for: move to an engine that plays
/// it, offer that move first, or stay. Choosing to stay withdraws the offers
/// pages hold.
public sealed record ChooseProtectedMediaFallback(ProtectedMediaFallback Fallback) : Intent {
    #region Actions - Device

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => {
        app.Device.ChooseProtectedMediaFallback(Fallback, changes);
        Fallback.Withdraw(app.Pages, changes);
    });

    #endregion
}
