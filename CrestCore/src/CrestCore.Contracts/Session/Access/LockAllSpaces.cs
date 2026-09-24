namespace CrestCore.Contracts;

/// Locks every Space again, cancelling a request waiting to unlock one. When
/// `SceneWentInactive`, the scene may only have made way for the system's own
/// authentication prompt, so while a request is waiting nothing locks.
public sealed record LockAllSpaces(bool SceneWentInactive) : SpaceAccessIntent;
