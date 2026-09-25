namespace CrestCore.Contracts;

/// Another Space a lift may drop on, and the rule that refuses the drop, or
/// null when it may land there.
public sealed record SpaceDropTarget(Guid SpaceId, Rejection? Refusal);
