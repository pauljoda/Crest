namespace CrestCore.Contracts;

/// This process's access to one Space's profile: whether it holds the grant
/// that unlocking gives, and whether a request to unlock it is waiting on the
/// device owner. A Space that asks for authentication shows only while its
/// profile is unlocked; one that opens freely always shows.
public sealed record SpaceLockChanged(Guid SpaceId, Guid ProfileId, bool IsUnlocked, bool IsAuthenticating) : Change;
