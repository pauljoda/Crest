using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether the extensions the engine of `Engine` keeps for Space `SpaceId`
/// may change now, and when they may not, the rule that refuses it, so a menu
/// offers only what the core would accept: a private window's or a locked
/// Space's offers none.
public sealed record CanChangeExtensions(Guid SpaceId, EngineKind Engine) : Query<SendPermission> {
    #region Actions - Answering

    internal override SendPermission Answer(CrestApp app) {
        try {
            app.Extensions.Reachable(SpaceId, Engine);
            return new(Refusal: null);
        } catch (Rejected refused) {
            return new(refused.Rejection);
        }
    }

    #endregion
}
