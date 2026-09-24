namespace CrestCore.Contracts;

/// <summary>A Space's split metadata now reads as <see cref="Groups"/>.</summary>
public sealed record SplitGroupsChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<SplitGroupState> Groups) : Change;
