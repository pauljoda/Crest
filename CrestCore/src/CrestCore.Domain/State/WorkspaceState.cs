namespace CrestCore.Domain;

public sealed record WorkspaceState(WorkspaceId Id, SpaceId? DefaultSpaceId, SpaceId? SelectedSpaceId,
    IReadOnlyList<SpaceState> Spaces, IReadOnlyList<WindowState> Windows,
    IReadOnlyList<SpaceDeletionState>? SpaceDeletions = null);
