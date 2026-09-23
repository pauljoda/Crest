namespace CrestCore.Domain;

/// Durable browsing data only. Which Space or tab a window shows is UI state and
/// never part of the workspace; windows keep their own selection records.
public sealed record WorkspaceState(Guid Id, Guid? DefaultSpaceId,
    IReadOnlyList<SpaceState> Spaces, IReadOnlyList<WindowState> Windows,
    IReadOnlyList<SpaceDeletionState>? SpaceDeletions = null);
