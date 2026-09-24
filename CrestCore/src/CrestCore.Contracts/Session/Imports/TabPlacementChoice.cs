namespace CrestCore.Contracts;

/// A reviewed tab that moves to `Placement`.
public sealed record TabPlacementChoice(Guid TabId, TabPlacement Placement);
