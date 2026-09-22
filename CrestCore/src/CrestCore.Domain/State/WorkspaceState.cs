namespace CrestCore.Domain;

public sealed record WorkspaceState(Guid Id, Guid? DefaultSpaceId, Guid? SelectedSpaceId,
    IReadOnlyList<SpaceState> Spaces, IReadOnlyList<WindowState> Windows,
    IReadOnlyList<SpaceDeletionState>? SpaceDeletions = null);
