namespace CrestCore.Contracts;

/// Shows the Space before or after the one a window shows, among the Spaces it
/// may show in the session's order, which leaves out one being deleted,
/// wrapping at both ends, as `ShowSpace` shows it. Publishes nothing when the
/// window may show fewer than two Spaces.
public sealed record ShowAdjacentSpace(Guid WindowId, AdjacentDirection Direction) : WindowIntent;
