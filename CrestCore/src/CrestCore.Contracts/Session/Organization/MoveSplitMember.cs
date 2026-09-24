namespace CrestCore.Contracts;

/// Moves a tab to member `Index` of its split, clamped to the split's members.
public sealed record MoveSplitMember(Guid WorkspaceId, Guid SpaceId, Guid TabId, int Index) : SessionIntent(WorkspaceId);
