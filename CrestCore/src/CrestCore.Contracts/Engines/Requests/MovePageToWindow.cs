namespace CrestCore.Contracts;

/// Moves the page into the engine's part of the window `WindowId` names,
/// keeping its history, renderer and extension identity, before the window
/// shows it.
public sealed record MovePageToWindow(Guid PageId, Guid WindowId) : PageRequest<bool>;
