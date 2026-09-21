namespace CrestCore.Domain;

public sealed record SpaceDeletionState(SpaceId Space, ProfileId Profile, DateTimeOffset RequestedAt, bool Completed = false);
