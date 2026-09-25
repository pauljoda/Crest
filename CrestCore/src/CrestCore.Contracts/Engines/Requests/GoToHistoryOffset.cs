namespace CrestCore.Contracts;

/// Moves the page `Offset` entries through its engine's navigation history:
/// -1 goes back, 1 goes forward. False when the history has no such entry.
public sealed record GoToHistoryOffset(Guid PageId, int Offset) : PageRequest<bool>;
