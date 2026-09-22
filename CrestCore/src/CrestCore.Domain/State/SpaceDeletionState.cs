namespace CrestCore.Domain;

public sealed record SpaceDeletionState(Guid Space, Guid Profile, DateTimeOffset RequestedAt, bool Completed = false);
