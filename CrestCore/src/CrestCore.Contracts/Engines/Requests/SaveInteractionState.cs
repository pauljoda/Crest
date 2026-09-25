namespace CrestCore.Contracts;

/// The page's navigation history in the engine's own format, which
/// `RestoreInteractionState` brings back.
public sealed record SaveInteractionState(Guid PageId) : PageRequest<InteractionState>;
