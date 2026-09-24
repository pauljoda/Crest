namespace CrestCore.Contracts;

/// <summary>A workspace's own members now read as these: the Space a launch opens,
/// whether the session is still the disposable first-install seed, and the Space
/// deletions under way on this device.</summary>
public sealed record WorkspaceChanged(Guid WorkspaceId, Guid? DefaultSpaceId, bool IsDisposableSeed,
    IReadOnlyList<SpaceDeletionState> SpaceDeletions) : Change;
