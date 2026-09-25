namespace CrestCore.Contracts;

/// Restores navigation history `SaveInteractionState` saved, in place of the
/// page's first load of `ExpectedUrl`, which the history must show. A page
/// still being created restores once it exists. False when the history is
/// another page's or the page has already loaded.
public sealed record RestoreInteractionState(Guid PageId, byte[] State, string ExpectedUrl) : PageRequest<bool>;
